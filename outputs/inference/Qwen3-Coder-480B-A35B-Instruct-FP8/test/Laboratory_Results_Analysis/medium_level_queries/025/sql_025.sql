WITH troponin_first AS (
  -- Get first Troponin T (>0.01 ng/mL) per admission
  SELECT
    l.hadm_id,
    l.valuenum AS troponin_value
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valueuom = 'ng/mL'
    AND l.valuenum > 0.01
    AND l.valuenum IS NOT NULL
),
first_trop_per_admission AS (
  -- Get earliest Troponin T per admission
  SELECT
    hadm_id,
    MIN(charttime) AS first_charttime
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents AS l
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems AS d
    ON l.itemid = d.itemid
  WHERE
    LOWER(d.label) = 'troponin t'
    AND l.valueuom = 'ng/mL'
    AND l.valuenum > 0.01
    AND l.valuenum IS NOT NULL
  GROUP BY
    hadm_id
),
troponin_cleaned AS (
  -- Join to get the actual first Troponin T value
  SELECT
    tf.hadm_id,
    tf.troponin_value
  FROM
    troponin_first AS tf
  INNER JOIN
    first_trop_per_admission AS f
    ON tf.hadm_id = f.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.labevents AS l
    ON l.hadm_id = f.hadm_id
    AND l.charttime = f.first_charttime
),
eligible_admissions AS (
  -- Filter admissions by diagnosis: chest pain or AMI
  SELECT
    a.hadm_id
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions AS a
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd AS di
    ON a.hadm_id = di.hadm_id
  INNER JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses AS d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) IN ('chest pain', 'acute myocardial infarction')
  GROUP BY
    a.hadm_id
),
eligible_patients AS (
  -- Filter patients by age and gender
  SELECT
    p.subject_id
  FROM
    physionet-data.mimiciv_3_1_hosp.patients AS p
  WHERE
    p.anchor_age BETWEEN 58 AND 68
    AND p.gender = 'F'
)
-- Final selection and aggregation
SELECT
  AVG(t.troponin_value) AS mean_troponin,
  STDDEV(t.troponin_value) AS stddev_troponin,
  MIN(t.troponin_value) AS min_troponin,
  MAX(t.troponin_value) AS max_troponin
FROM
  troponin_cleaned AS t
INNER JOIN
  eligible_admissions AS a
  ON t.hadm_id = a.hadm_id
INNER JOIN
  physionet-data.mimiciv_3_1_hosp.admissions AS adm
  ON t.hadm_id = adm.hadm_id
INNER JOIN
  eligible_patients AS p
  ON adm.subject_id = p.subject_id;