SELECT
      quintile,
      thirty_day_mortality,
      ards_flag,
      CASE
        WHEN hospital_expire_flag = 0 THEN DATE_DIFF(dischtime, admittime, DAY)
      END AS los
    FROM risk_quintiles
  ),;