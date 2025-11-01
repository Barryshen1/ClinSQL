WITH copd_admissions AS (
  SELECT DISTINCT a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE p.gender = 'F'
    AND (
      (d.icd_version = 9 AND d.icd_code = '496')
      OR (d.icd_version = 10 AND d.icd_code LIKE 'J44%')
    )
),
creatinine_24h AS (
  SELECT 
    a.hadm_id,
    AVG(l.valuenum) AS avg_creat
  FROM copd_admissions ca
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON ca.hadm_id = a.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l
    ON a.hadm_id = l.hadm_id
  WHERE l.itemid = 50912  -- Serum creatinine item ID
    AND l.valuenum IS NOT NULL
    AND l.charttime >= a.admittime
    AND l.charttime < TIMESTAMP_ADD(a.admittime, INTERVAL 24 HOUR)
  GROUP BY a.hadm_id
)
SELECT 
  APPROX_QUANTILES(avg_creat, 100)[OFFSET(75)] AS p75_avg_creat
FROM creatinine_24h;