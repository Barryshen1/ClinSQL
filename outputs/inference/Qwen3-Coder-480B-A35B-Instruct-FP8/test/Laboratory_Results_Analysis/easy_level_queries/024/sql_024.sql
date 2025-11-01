WITH sepsis_admissions AS (
  SELECT DISTINCT
    di.hadm_id,
    di.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%sepsis%'
),
male_sepsis_admissions AS (
  SELECT
    sa.hadm_id,
    sa.subject_id
  FROM
    sepsis_admissions sa
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON sa.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
),
first_platelet AS (
  SELECT
    le.hadm_id,
    le.valuenum AS platelet,
    ROW_NUMBER() OVER (PARTITION BY le.hadm_id ORDER BY le.charttime) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems dl
    ON le.itemid = dl.itemid
  JOIN
    male_sepsis_admissions msa
    ON le.hadm_id = msa.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions a
    ON le.hadm_id = a.hadm_id
  WHERE
    LOWER(dl.label) = 'platelet'
    AND le.valuenum IS NOT NULL
    AND le.valuenum > 0
    AND le.charttime >= a.admittime
    AND le.charttime <= a.dischtime
)
SELECT
  STDDEV_SAMP(platelet) AS platelet_count_sd
FROM
  first_platelet
WHERE
  rn = 1;