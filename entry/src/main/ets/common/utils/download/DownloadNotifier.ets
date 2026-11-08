import { notificationManager } from '@kit.NotificationKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { _QhState } from '../../../entryability/AppState';
import { createLogger } from '../app/Logger';
import { appSettings } from '../../entity/SettingsModel';

const logger = createLogger('DownloadNotifier')

/**
 * 下载进度通知（系统 downloadTemplate 进度条模板）：
 * - 首次发布前 requestEnableNotification 弹窗申请授权（拒绝则静默跳过，不再打扰）
 * - isSupportTemplate 结果缓存；不支持的设备上全部静默跳过
 * - 通知 id 由下载路径哈希派生，同一任务的进度更新覆盖同一条通知
 */
export class DownloadNotifier {
  private static prepared: boolean = false
  private static supported: boolean = true

  /** 首次使用前申请通知授权并探测 downloadTemplate 支持（仅执行一次；设置关闭通知时不申请授权） */
  static async prepare(): Promise<void> {
    if (DownloadNotifier.prepared) {
      return
    }
    if (!appSettings.download_notify) {
      return
    }
    DownloadNotifier.prepared = true
    try {
      await notificationManager.requestEnableNotification(_QhState.Context)
    } catch (e) {
      logger.debug(`requestEnableNotification: ${e}`)
    }
    try {
      DownloadNotifier.supported = await notificationManager.isSupportTemplate('downloadTemplate')
    } catch (e) {
      DownloadNotifier.supported = false
    }
  }

  /** 发布/更新下载进度通知（percent 0~100，-1 = 未知显示 0；subtitle 为「已下载/总大小 · 速度」副标题） */
  static publishProgress(id: number, fileName: string, percent: number, subtitle: string): void {
    if (!DownloadNotifier.prepared || !DownloadNotifier.supported || !appSettings.download_notify) {
      return
    }
    const clamped: number = percent >= 0 ? Math.max(0, Math.min(100, Math.floor(percent))) : 0
    // downloadTemplate 只渲染 data 中的 title/fileName/progressValue（normal.text 不显示）：
    // title 放文件名，fileName 槽位放副标题（大小/速度信息展示在进度条下方）
    const sub: string = subtitle !== '' ? subtitle : `${clamped}%`
    const request: notificationManager.NotificationRequest = {
      id: id,
      notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: fileName,
          text: sub,
          additionalText: fileName
        }
      },
      template: {
        name: 'downloadTemplate',
        data: {
          'title': fileName,
          'fileName': sub,
          'progressValue': clamped
        }
      }
    }
    notificationManager.publish(request).catch((e: BusinessError) => {
      logger.debug(`publish progress failed: ${e.code}`)
    })
  }

  /** 发布留存失败通知（同 id 覆盖进度条通知；不依赖 downloadTemplate，不支持模板的设备也生效） */
  static publishFailed(id: number, fileName: string): void {
    if (!DownloadNotifier.prepared || !appSettings.download_notify) {
      return
    }
    const request: notificationManager.NotificationRequest = {
      id: id,
      notificationSlotType: notificationManager.SlotType.CONTENT_INFORMATION,
      content: {
        notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
        normal: {
          title: _QhState.Context.resourceManager.getStringSync($r('app.string.download_failed').id),
          text: fileName,
          additionalText: fileName
        }
      }
    }
    notificationManager.publish(request).catch((e: BusinessError) => {
      logger.debug(`publish failed-notification failed: ${e.code}`)
    })
  }

  /** 取消通知（完成/失败/暂停后移除进度条） */
  static cancel(id: number): void {
    notificationManager.cancel(id).catch((e: BusinessError) => {
      logger.debug(`cancel notification failed: ${e.code}`)
    })
  }
}
