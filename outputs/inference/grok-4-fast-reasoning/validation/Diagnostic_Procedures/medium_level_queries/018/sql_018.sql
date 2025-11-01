WITH qualifying_admissions AS (
  SELECT 
    a.hadm_id,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4 days'
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 5 AND 7 THEN '5-7 days'
    END AS stay_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND (p.anchor_age + EXTRACT(YEAR FROM a.admittime) - p.anchor_year) BETWEEN 80 AND 90
    AND TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) BETWEEN 1 AND 7
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.hadm_id = a.hadm_id
        AND (
          (di.icd_version = 9 AND di.icd_code IN ('430', '431', '432'))
          OR
          (di.icd_version = 10 AND (di.icd_code LIKE 'I60%' OR di.icd_code LIKE 'I61%' OR di.icd_code LIKE 'I62%'))
        )
    )
),
ultrasound_counts AS (
  SELECT 
    pi.hadm_id,
    COUNT(*) AS num_ultrasounds
  FROM `physionet-data.mimiciv_3_1_hosp.procedures_icd` pi
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip 
    ON pi.icd_code = dip.icd_code AND pi.icd_version = dip.icd_version
  WHERE LOWER(dip.long_title) LIKE '%ultrasound%'
  GROUP BY pi.hadm_id
)
SELECT 
  qa.stay_group,
  AVG(COALESCE(uc.num_ultrasounds, 0)) AS mean_ultrasounds,
  MIN(COALESCE(uc.num_ultrasounds, 0)) AS min_ultrasounds,
  MAX(COALESCE(uc.num_ultrasounds, 0)) AS max_ultrasounds
FROM qualifying_admissions qa
LEFT JOIN ultrasound_counts uc 
  ON qa.hadm_id = uc.hadm_id
GROUP BY qa.stay_group
ORDER BY 
  CASE 
    WHEN qa.stay_group = '1-4 days' THEN 1 
    ELSE 2 
  END;