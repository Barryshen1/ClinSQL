WITH sepsis_admissions AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions a
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients p
    ON a.subject_id = p.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd di
    ON a.hadm_id = di.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON di.icd_code = d.icd_code AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%sepsis%'
    AND p.gender = 'M'
),
first_platelet AS (
  SELECT
    l.hadm_id,
    l.valuenum AS platelet_count,
    ROW_NUMBER() OVER (PARTITION BY l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents l
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'platelets'
    AND l.valuenum IS NOT NULL
)
SELECT
  STDDEV_SAMP(fp.platelet_count) AS platelet_stddev
FROM
  sepsis_admissions sa
JOIN
  first_platelet fp
  ON sa.hadm_id = fp.hadm_id
WHERE
  fp.rn = 1;