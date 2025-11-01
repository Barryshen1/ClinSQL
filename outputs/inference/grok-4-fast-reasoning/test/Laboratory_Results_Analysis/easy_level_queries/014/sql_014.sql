WITH cohort AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    a.dischtime, 
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'F'
    AND a.hospital_expire_flag = 0
    AND p.anchor_age + EXTRACT(YEAR FROM a.admittime) - 2008 = 45
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
      WHERE di.subject_id = a.subject_id
        AND di.hadm_id = a.hadm_id
        AND di.seq_num = 1
        AND (
          (di.icd_version = 9 AND di.icd_code LIKE '578%')
          OR (di.icd_version = 10 AND di.icd_code = 'K922')
        )
    )
)
SELECT 
  APPROX_QUANTILES(valuenum, 4)[OFFSET(3)] AS p75_discharge_hgb_g_per_dl
FROM (
  SELECT 
    le.valuenum,
    ROW_NUMBER() OVER (PARTITION BY c.hadm_id ORDER BY le.charttime DESC) AS rn
  FROM cohort c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le 
    ON le.subject_id = c.subject_id 
    AND le.hadm_id = c.hadm_id
  WHERE le.itemid = 51222
    AND le.valuenum IS NOT NULL
    AND DATE(le.charttime) = DATE(c.dischtime)
) 
WHERE rn = 1;