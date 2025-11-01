WITH copd_admissions AS (
  SELECT DISTINCT
    a.subject_id,
    a.hadm_id,
    a.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code
    AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age = 56
    AND (
      LOWER(dicd.long_title) LIKE '%chronic obstructive%'
      OR LOWER(dicd.long_title) LIKE '%copd%'
      OR LOWER(dicd.long_title) LIKE '%emphysema%'
    )
),

creatinine_events AS (
  SELECT
    c.hadm_id,
    -- normalize to mg/dL when reported in umol/L (divide by 88.4); otherwise keep reported numeric value
    CASE
      WHEN le.valuenum IS NULL THEN NULL
      WHEN LOWER(COALESCE(le.valueuom, '')) LIKE '%umol%' THEN le.valuenum / 88.4
      ELSE le.valuenum
    END AS creat_mg_dl
  FROM copd_admissions c
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON c.hadm_id = le.hadm_id
    AND c.subject_id = le.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` li
    ON le.itemid = li.itemid
  WHERE LOWER(li.label) LIKE '%creatinine%'
    AND le.valuenum IS NOT NULL
    -- restrict to first 24 hours after hospital admission
    AND le.charttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 24 HOUR)
),

avg_by_admission AS (
  SELECT
    hadm_id,
    AVG(creat_mg_dl) AS avg_creatinine
  FROM creatinine_events
  GROUP BY hadm_id
)

SELECT
  (APPROX_QUANTILES(avg_creatinine, 4))[OFFSET(3)] AS creatinine_75th_percentile_mg_per_dL,
  COUNT(*) AS n_admissions_with_creatinine
FROM avg_by_admission;