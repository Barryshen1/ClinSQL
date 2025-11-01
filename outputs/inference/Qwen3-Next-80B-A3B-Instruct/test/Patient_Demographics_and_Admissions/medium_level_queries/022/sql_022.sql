WITH filtered_admissions AS (
  SELECT 
    a.hadm_id,
    a.discharge_location,
    a.hospital_expire_flag,
    i.los
  FROM physionet-data.mimiciv_3_1_hosp.admissions a
  INNER JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_icu.icustays i
    ON a.hadm_id = i.hadm_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 81 AND 91
    AND a.admission_location = 'TRANSFER FROM HOSP'
    AND i.los IS NOT NULL
)
SELECT 
  CASE 
    WHEN hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
    WHEN discharge_location = 'HOME' THEN 'HOME'
    WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
  END AS discharge_stratum,
  AVG(los) AS mean_los,
  APPROX_QUANTILES(los, 100)[OFFSET(25)] AS p25_los,
  APPROX_QUANTILES(los, 100)[OFFSET(50)] AS p50_los,
  APPROX_QUANTILES(los, 100)[OFFSET(75)] AS p75_los,
  APPROX_QUANTILES(los, 100)[OFFSET(90)] AS p90_los,
  AVG(CASE WHEN los <= 10 THEN 1.0 ELSE 0.0 END) * 100 AS percent_le_10_days
FROM filtered_admissions
WHERE CASE 
        WHEN hospital_expire_flag = 1 THEN 'IN-HOSPITAL DEATH'
        WHEN discharge_location = 'HOME' THEN 'HOME'
        WHEN discharge_location = 'HOSPICE' THEN 'HOSPICE'
      END IS NOT NULL
GROUP BY discharge_stratum
ORDER BY discharge_stratum;