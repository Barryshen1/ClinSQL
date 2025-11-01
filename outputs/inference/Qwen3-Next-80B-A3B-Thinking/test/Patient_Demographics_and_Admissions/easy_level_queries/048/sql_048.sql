WITH los_data AS (
  SELECT 
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 79 AND 89
    AND a.dischtime IS NOT NULL
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE a.hadm_id = d.hadm_id
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%')
          OR (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
)
SELECT 
  PERCENTILE_CONT(los_days, 0.25) OVER () AS q1,
  PERCENTILE_CONT(los_days, 0.75) OVER () AS q3,
  PERCENTILE_CONT(los_days, 0.75) OVER () - PERCENTILE_CONT(los_days, 0.25) OVER () AS iqr
FROM los_data
LIMIT 1;