WITH sepsis_admissions AS (
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` adm
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` pat
      ON adm.subject_id = pat.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
      ON adm.hadm_id = dx.hadm_id
  WHERE
    pat.gender = 'M'
    AND (
      -- ICD-10 sepsis codes
      (dx.icd_version = 10 AND (
        dx.icd_code LIKE 'A40%' OR
        dx.icd_code LIKE 'A41%'
      ))
      -- ICD-9 sepsis codes
      OR (dx.icd_version = 9 AND (
        dx.icd_code IN ('99591', '99592', '78552')
      ))
    )
),
platelet_itemids AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%platelet%'
),
first_platelet AS (
  SELECT
    sa.subject_id,
    sa.hadm_id,
    le.charttime,
    le.valuenum
  FROM
    sepsis_admissions sa
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
      ON sa.subject_id = le.subject_id
      AND sa.hadm_id = le.hadm_id
    INNER JOIN platelet_itemids pi
      ON le.itemid = pi.itemid
  WHERE
    le.valuenum IS NOT NULL
    AND le.charttime >= sa.admittime
    AND le.charttime <= sa.dischtime
),
first_platelet_per_admission AS (
  SELECT
    subject_id,
    hadm_id,
    MIN(charttime) AS first_charttime
  FROM first_platelet
  GROUP BY subject_id, hadm_id
),
admission_platelet AS (
  SELECT
    fp.subject_id,
    fp.hadm_id,
    fp.valuenum AS platelet_count
  FROM
    first_platelet fp
    INNER JOIN first_platelet_per_admission fpp
      ON fp.subject_id = fpp.subject_id
      AND fp.hadm_id = fpp.hadm_id
      AND fp.charttime = fpp.first_charttime
)
SELECT
  STDDEV_SAMP(platelet_count) AS sd_admission_platelet_count
FROM
  admission_platelet
;