WITH copd_admissions AS (
  SELECT DISTINCT ad.subject_id, ad.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON p.subject_id = ad.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON ad.subject_id = di.subject_id AND ad.hadm_id = di.hadm_id
  WHERE p.gender = 'F'
    AND (
      (di.icd_version = 10 AND di.icd_code LIKE 'J44%')
      OR (di.icd_version = 9 AND (
        di.icd_code = '490' OR di.icd_code LIKE '491%' OR di.icd_code LIKE '492%' OR di.icd_code = '496'
      ))
    )
),
avg_creatinine AS (
  SELECT 
    ca.hadm_id,
    AVG(le.valuenum) AS avg_creat
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  INNER JOIN copd_admissions ca
    ON le.subject_id = ca.subject_id AND le.hadm_id = ca.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` ad
    ON le.hadm_id = ad.hadm_id
  WHERE le.itemid = 50912
    AND le.valuenum IS NOT NULL
    AND le.charttime >= ad.admittime
    AND le.charttime < TIMESTAMP_ADD(ad.admittime, INTERVAL 1 DAY)
  GROUP BY ca.hadm_id
)
SELECT 
  APPROX_QUANTILES(avg_creat, 4)[OFFSET(3)] AS p75th_percentile_avg_creatinine
FROM avg_creatinine;