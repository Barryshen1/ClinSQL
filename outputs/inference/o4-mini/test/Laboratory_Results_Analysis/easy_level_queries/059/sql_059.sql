WITH sepsis_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.dischtime
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
      ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d
      ON a.subject_id = d.subject_id
      AND a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` AS di
      ON d.icd_code = di.icd_code
      AND d.icd_version = di.icd_version
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 93
    AND LOWER(di.long_title) LIKE '%sepsis%'
),
platelet_on_discharge AS (
  SELECT
    la.subject_id,
    la.hadm_id,
    le.valuenum AS platelet_count
  FROM
    sepsis_admissions AS la
    JOIN `physionet-data.mimiciv_3_1_hosp.labevents` AS le
      ON la.subject_id = le.subject_id
      AND la.hadm_id = le.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_labitems` AS li
      ON le.itemid = li.itemid
  WHERE
    DATE(le.charttime) = DATE(la.dischtime)
    AND LOWER(li.label) LIKE '%platelet%'
    AND le.valuenum IS NOT NULL
  QUALIFY
    ROW_NUMBER() OVER (
      PARTITION BY la.hadm_id
      ORDER BY le.charttime DESC
    ) = 1
)
SELECT
  APPROX_QUANTILES(platelet_count, 100)[OFFSET(75)] AS platelet_75th_percentile
FROM
  platelet_on_discharge;