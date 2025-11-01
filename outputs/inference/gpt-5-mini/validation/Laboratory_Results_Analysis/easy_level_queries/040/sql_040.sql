WITH dka_adms AS (
  -- female patients age 58 with a diagnosis description containing "ketoacidosis"
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
    ON a.subject_id = di.subject_id AND a.hadm_id = di.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dic
    ON di.icd_code = dic.icd_code AND di.icd_version = dic.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age = 58
    AND LOWER(dic.long_title) LIKE '%ketoacidosis%'
),

glucose_itemids AS (
  -- pick lab itemids related to glucose (serum/blood/plasma)
  SELECT DISTINCT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%glucose%'
    AND (
      LOWER(COALESCE(fluid, '')) LIKE '%blood%'
      OR LOWER(COALESCE(fluid, '')) LIKE '%ser%'
      OR LOWER(COALESCE(fluid, '')) LIKE '%plasma%'
      OR COALESCE(fluid, '') = ''
    )
),

peak_per_adm AS (
  -- peak glucose (numeric) per admission during that hospital stay
  SELECT
    d.hadm_id,
    MAX(le.valuenum) AS peak_glucose,
    ANY_VALUE(le.valueuom) AS unit
  FROM dka_adms d
  JOIN `physionet-data.mimiciv_3_1_hosp.labevents` le
    ON le.hadm_id = d.hadm_id
  JOIN glucose_itemids gi
    ON le.itemid = gi.itemid
  WHERE le.valuenum IS NOT NULL
    AND le.charttime BETWEEN d.admittime AND d.dischtime
  GROUP BY d.hadm_id
)

-- median of the admission-level peaks (approximate with high resolution)
SELECT
  COUNT(*) AS num_admissions_with_glucose,
  (SELECT APPROX_QUANTILES(peak_glucose, 1001)[OFFSET(500)] FROM peak_per_adm) AS median_peak_glucose,
  (SELECT ANY_VALUE(unit) FROM peak_per_adm) AS example_unit
FROM peak_per_adm;