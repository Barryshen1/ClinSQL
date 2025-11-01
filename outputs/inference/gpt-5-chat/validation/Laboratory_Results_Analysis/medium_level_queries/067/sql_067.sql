WITH ami_cases AS (
  SELECT DISTINCT
    pat.subject_id,
    adm.hadm_id,
    pat.gender,
    pat.anchor_age,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.patients` pat
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` adm
    ON pat.subject_id = adm.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
    ON adm.hadm_id = dx.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` ddx
    ON dx.icd_code = ddx.icd_code 
   AND dx.icd_version = ddx.icd_version
  WHERE pat.gender = 'F'
    AND pat.anchor_age BETWEEN 52 AND 62
    AND (
      (dx.icd_version = 9 AND dx.icd_code LIKE '410%')
      OR (dx.icd_version = 10 AND (dx.icd_code LIKE 'I21%' OR dx.icd_code LIKE 'I22%'))
    )
),
first_trop_t AS (
  SELECT
    lc.subject_id,
    lc.hadm_id,
    MIN(le.charttime) AS first_charttime
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  JOIN ami_cases lc
    ON le.hadm_id = lc.hadm_id
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
  GROUP BY lc.subject_id, lc.hadm_id
),
first_trop_val AS (
  SELECT
    ft.subject_id,
    ft.hadm_id,
    le.valuenum,
    le.valueuom
  FROM first_trop_t ft
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON ft.hadm_id = le.hadm_id
   AND ft.first_charttime = le.charttime
  JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` dl
    ON le.itemid = dl.itemid
  WHERE LOWER(dl.label) LIKE '%troponin t%'
    AND le.valuenum IS NOT NULL
)
SELECT
  COUNT(DISTINCT a.subject_id) AS num_patients,
  COUNT(DISTINCT a.hadm_id) AS num_admissions,
  ROUND(AVG(a.anchor_age),2) AS mean_age,
  ROUND(AVG(TIMESTAMP_DIFF(a.dischtime, a.admittime, HOUR)/24),2) AS mean_los_days,
  ROUND(AVG(f.valuenum),4) AS mean_first_trop_t,
  ROUND(MIN(f.valuenum),4) AS min_first_trop_t,
  ROUND(MAX(f.valuenum),4) AS max_first_trop_t,
  SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS num_deaths,
  ROUND(100.0 * SUM(CASE WHEN a.hospital_expire_flag = 1 THEN 1 ELSE 0 END) / COUNT(DISTINCT a.hadm_id), 1) AS mortality_rate_percent
FROM ami_cases a
JOIN first_trop_val f
  ON a.subject_id = f.subject_id AND a.hadm_id = f.hadm_id
WHERE f.valuenum > 0.01;