### 📊 매출 관리 API 명세 (Toggle List)
<details>
<summary><b><code>GET</code> /sales/hourly</b> - 기간별 시간대별 매출</summary>

- **기능**: 날짜별·시간대별 매출, 전체/홀/배달, 기간 총 매출·주문 수
- **Query DTO**: `GetHourlySalesDto`
- **응답 DTO**:
  ```ts
  {
    branch_id: number
    branch_name: string
    from_date: string      // yyyy-MM-dd
    to_date: string        // yyyy-MM-dd
    sales_amount: number   // 기간 전체 총 매출 (참고용)
    order_count: number    // 기간 전체 총 주문 수 (참고용)
    hourly_sales: [
      {
        hour: string       // "00:00 - 00:59" 형식 (24시간)
        sales: [
          {
            date: string             // yyyy-MM-dd
            total_sales_amount: number
            total_order_count: number
            hall_sales_amount: number
            hall_order_count: number
            delivery_sales_amount: number
            delivery_order_count: number
          }
        ]
      }
    ]
  }
  ```
</details>

<details>
<summary><b><code>GET</code> /sales/daily</b> - 일자별(월간) 매출</summary>

- **기능**: 월 기준 일자별 매출 반환
- **Query DTO**: `GetDailySalesDto`
- **응답 DTO**: `DailySalesResponseDto`
- **비고**: `req.user` 기반 데이터 필터링
</details>

<details>
<summary><b><code>GET</code> /sales/daily/detail</b> - 일자별 매출 상세</summary>

- **기능**: 특정 지점 및 특정 일자의 상세 매출 내역
- **Query DTO**: `GetDailySalesDetailDto`
- **응답 DTO**: `DailySalesDetailResponseDto`
</details>

<details>
<summary><b><code>GET</code> /sales/monthly</b> - 월별(연간) 매출</summary>

- **기능**: 기준 연월부터 12개월간 지점별·월별 매출/주문 건수
- **Query DTO**: `GetMonthlySalesDto`
- **응답 DTO**: `MonthlySalesResponseDto`
</details>

<details>
<summary><b><code>GET</code> /sales/monthly/detail</b> - 월별 매출 상세</summary>

- **기능**: 특정 지점 및 특정 연월의 상세 매출 내역
- **Query DTO**: `GetMonthlySalesDetailDto`
- **응답 DTO**: `MonthlySalesDetailResponseDto`
</details>

<details>
<summary><b><code>GET</code> /sales/monthly/year</b> - 연도별 월별 매출</summary>

- **기능**: 특정 연도 1~12월 월별 순매출 및 주문 수
- **Query DTO**: `GetMonthlySalesByYearDto`
- **응답 DTO**: `MonthlySalesByYearResponseDto`
- **비고**: `req.user` 사용
</details>

<details>
<summary><b><code>GET</code> /sales/monthly/comparison</b> - 월 총매출 비교</summary>

- **기능**: 전월 대비 및 전년 동월 대비 성장률 지표
- **Query DTO**: `GetMonthlyComparisonDto`
- **응답 DTO**: `MonthlyComparisonResponseDto`
</details>

<details>
<summary><b><code>GET</code> /sales/platform</b> - 플랫폼별 매출</summary>

- **기능**: 배달 플랫폼별 매출 통계
- **Query DTO**: `GetPlatformSalesDto`
- **응답 DTO**: `PlatformSalesResponseDto`
- **비고**: 관리 권한 필요, `req.user` 사용
</details>