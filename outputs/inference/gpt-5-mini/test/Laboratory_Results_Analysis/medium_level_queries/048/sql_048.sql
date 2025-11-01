WITH troponin_items AS (
  -- Identify troponin T lab itemids by label text (approximate; replace with curated itemid list if available)
  SELECT itemid, label
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE (
    LOWER(label) LIKE '%troponin t%' OR
    LOWER(label) LIKE '%troponin-t%' OR
    LOWER(label) LIKE '%high-sensitivity troponin t%' OR
    LOWER(label) LIKE '%hs-tnt%' OR
    LOWER(label) LIKE '%troponin t, hs%'
  )
),
lab_values AS (
  -- Pull troponin lab events and convert to ng/mL where possible
  SELECT
    le.subject_id,
    le.hadm_id,
    le.charttime,
    le.labevent_id,
    le.valuenum,
    le.valueuom,
    CASE
      WHEN le.valuenum IS NULL THEN NULL
      WHEN LOWER(COALESCE(le.valueuom, '')) LIKE '%ng/l%' THEN le.valuenum / 1000.0
      WHEN LOWER(COALESCE(le.valueuom, '')) LIKE '%pg/ml%' THEN le.valuenum / 1000.0
      WHEN LOWER(COALESCE(le.valueuom, '')) LIKE '%pg/l%' THEN le.valuenum / 1000000.0
      WHEN LOWER(COALESCE(le.valueuom, '')) LIKE '%ng/ml%' THEN le.valuenum
      ELSE NULL
    END AS hs_tnt_ng_ml
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` le
  JOIN troponin_items ti
    ON le.itemid = ti.itemid
  WHERE le.valuenum IS NOT NULL
),
first_troponin_per_adm AS (
  -- Select the earliest troponin event per admission and require a convertible numeric value
  SELECT subject_id, hadm_id, charttime, hs_tnt_ng_ml
  FROM (
    SELECT
      lv.*,
      ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY charttime ASC, labevent_id ASC) AS rn
    FROM lab_values lv
  )
  WHERE rn = 1
    AND hs_tnt_ng_ml IS NOT NULL
),
ami_admissions AS (
  -- Admissions that have an AMI diagnosis (approximate by d_icd_diagnoses.long_title text)
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
    ON di.icd_code = d.icd_code
    AND di.icd_version = d.icd_version
  WHERE
    (
      LOWER(d.long_title) LIKE '%myocardial infarction%' OR
      LOWER(d.long_title) LIKE '%acute myocardial infarction%' OR
      LOWER(d.long_title) LIKE '%ami%'
    )
),
eligible_first_troponin AS (
  -- Join first troponin values to admissions/patients and AMI filter, apply age/gender, and apply threshold > 0.01 ng/mL
  SELECT f.subject_id, f.hadm_id, f.hs_tnt_ng_ml
  FROM first_troponin_per_adm f
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON f.hadm_id = a.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN ami_admissions am
    ON f.hadm_id = am.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 55 AND 65
    AND f.hs_tnt_ng_ml > 0.01
),
quartiles AS (
  -- Compute approximate quartiles (returns array: [min, Q1, median, Q3, max])
  SELECT APPROX_QUANTILES(hs_tnt_ng_ml, 4) AS qarr
  FROM eligible_first_troponin
)
SELECT
  COUNT(DISTINCT e.subject_id) AS patient_count,
  COUNT(DISTINCT e.hadm_id) AS admission_count,
  ROUND(AVG(e.hs_tnt_ng_ml), 6) AS hs_tnt_mean_ng_per_ml,
  q.qarr[OFFSET(2)] AS hs_tnt_median_ng_per_ml,
  q.qarr[OFFSET(1)] AS hs_tnt_q1_ng_per_ml,
  q.qarr[OFFSET(3)] AS hs_tnt_q3_ng_per_ml,
  q.qarr[OFFSET(3)] - q.qarr[OFFSET(1)] AS hs_tnt_iqr_ng_per_ml
FROM eligible_first_troponin e
CROSS JOIN quartiles q;