import { http } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { homeHtmlRefresh } from './HomeHtmlRefresh';

/**
 * 每日一言（今日诗词）：主页地址栏/搜索框默认词数据源
 * 会话内取一次，成功后通知 HTML 主页重推配置
 */
@ObservedV2
export class HitokotoService {
  @Trace quote: string = ''
  private fetching: boolean = false

  ensure(): void {
    if (this.quote !== '' || this.fetching) {
      return
    }
    this.fetching = true
    const client = http.createHttp()
    client.request('https://v1.jinrishici.com/all.txt', {
      method: http.RequestMethod.GET,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 8000,
      readTimeout: 8000
    })
      .then((resp: http.HttpResponse) => {
        if (resp.responseCode === 200 && typeof resp.result === 'string') {
          const text: string = resp.result.trim()
          if (text !== '') {
            this.quote = text
            homeHtmlRefresh.request()
          }
        }
      })
      .catch((error: BusinessError) => {
        this.fetching = false
      })
      .finally(() => {
        this.fetching = false
        client.destroy()
      })
  }
}

export const hitokoto = new HitokotoService()
