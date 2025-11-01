WITH sepsis_admissions AS (
  SELECT DISTINCT adm.subject_id, adm.hadm_id, adm.admittime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` adm
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
    ON adm.subject_id = pat.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` diag
    ON adm.hadm_id = diag.hadm_id
  WHERE pat.gender = 'F'
    AND pat.anchor_age = 76
    AND (
      (diag.icd_version = 9 AND (
        diag.icd_code LIKE '038%' OR
        diag.icd_code IN ('99591','99592')
      ))
      OR
      (diag.icd_version = 10 AND (
        diag.icd_code LIKE 'A40%' OR
        diag.icd_code LIKE 'A41%'
      ))
    )
),
platelet_labs AS (
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
    AND LOWER(fluid) = 'blood'
),
first24h_platelet AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    AVG(le.valuenum) AS avg_platelet_24h
  FROM sepsis_admissions sa
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON sa.hadm_id = le.hadm_id
  JOIN platelet_labs pl
    ON le.itemid = pl.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime >= sa.admittime
    AND le.charttime < DATETIME_ADD(sa.admittime, INTERVAL 24 HOUR)
  GROUP BY sa.subject_id, sa.hadm_id
)
SELECT
  percentile_cont(avg_platelet_24h, 0.5) OVER() AS median_platelet_avg_first24h
FROM first24h_platelet
LIMIT 1;