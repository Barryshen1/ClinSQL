SELECT 
    *,
    CASE 
      WHEN hospital_expire_flag = 1 AND deathtime <= admittime + INTERVAL '30' DAY THEN 1
      WHEN hospital_expire_flag = 0 AND 
           dod IS NOT NULL AND
           dod <= DATE_ADD(CAST(admittime AS DATE), INTERVAL 30 DAY)
      THEN 1
      ELSE 0
    END AS died_30day
  FROM quintiles
);