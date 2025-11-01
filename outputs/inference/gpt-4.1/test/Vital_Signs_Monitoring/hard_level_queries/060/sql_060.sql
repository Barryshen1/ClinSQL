WITH cohort AS (
  -- Select male ICU patients aged 78-88
  SELECT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los,
    p.anchor_age,
    p.gender
  FROM physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN physionet-data.mimiciv_3_1_hosp.patients p
    ON icu.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 78 AND 88
),
hhs_cases AS (
  -- Identify HHS cases by ICD codes
  SELECT DISTINCT c.subject_id, c.hadm_id, c.stay_id
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON c.hadm_id = d.hadm_id
  WHERE
    (
      (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^2502')) -- ICD-9 HHS
      OR
      (d.icd_version = 10 AND d.icd_code IN ('E110', 'E100', 'E130', 'E140')) -- ICD-10 HHS
    )
),
controls AS (
  -- Controls: same cohort, no HHS diagnosis
  SELECT c.subject_id, c.hadm_id, c.stay_id
  FROM cohort c
  WHERE NOT EXISTS (
    SELECT 1
    FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    WHERE c.hadm_id = d.hadm_id
      AND (
        (d.icd_version = 9 AND REGEXP_CONTAINS(d.icd_code, r'^2502'))
        OR
        (d.icd_version = 10 AND d.icd_code IN ('E110', 'E100', 'E130', 'E140'))
      )
  )
),
vital_itemids AS (
  -- Get itemids for vital signs
  SELECT itemid, LOWER(label) AS label, lownormalvalue, highnormalvalue
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) IN (
    'heart rate', 'systolic blood pressure', 'diastolic blood pressure',
    'respiratory rate', 'temperature', 'spo2'
  )
),
vitals_48h AS (
  -- Get vital sign measurements in first 48h for cohort
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    ce.charttime,
    ce.itemid,
    ce.valuenum,
    vi.label,
    vi.lownormalvalue,
    vi.highnormalvalue,
    CASE
      WHEN ce.valuenum IS NULL THEN NULL
      WHEN vi.lownormalvalue IS NOT NULL AND ce.valuenum < vi.lownormalvalue THEN 1
      WHEN vi.highnormalvalue IS NOT NULL AND ce.valuenum > vi.highnormalvalue THEN 1
      ELSE 0
    END AS is_abnormal
  FROM cohort c
  JOIN physionet-data.mimiciv_3_1_icu.chartevents ce
    ON c.subject_id = ce.subject_id AND c.stay_id = ce.stay_id
  JOIN vital_itemids vi
    ON ce.itemid = vi.itemid
  WHERE ce.charttime BETWEEN c.intime AND TIMESTAMP_ADD(c.intime, INTERVAL 48 HOUR)
),
instability_scores AS (
  -- For each stay, calculate composite instability score and abnormal-vital burden
  SELECT
    subject_id,
    hadm_id,
    stay_id,
    COUNTIF(is_abnormal = 1) AS composite_instability_score,
    SAFE_DIVIDE(COUNTIF(is_abnormal = 1), COUNT(is_abnormal)) AS mean_abnormal_vital_burden
  FROM vitals_48h
  WHERE is_abnormal IS NOT NULL
  GROUP BY subject_id, hadm_id, stay_id
),
outcomes AS (
  -- Add LOS and mortality
  SELECT
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    i.composite_instability_score,
    i.mean_abnormal_vital_burden,
    c.los,
    a.hospital_expire_flag
  FROM cohort c
  LEFT JOIN instability_scores i
    ON c.subject_id = i.subject_id AND c.hadm_id = i.hadm_id AND c.stay_id = i.stay_id
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON c.hadm_id = a.hadm_id
),
final AS (
  -- Label HHS vs control
  SELECT
    o.*,
    CASE
      WHEN h.subject_id IS NOT NULL THEN 'HHS'
      ELSE 'Control'
    END AS group_label
  FROM outcomes o
  LEFT JOIN hhs_cases h
    ON o.subject_id = h.subject_id AND o.hadm_id = h.hadm_id AND o.stay_id = h.stay_id
  -- Only include stays with at least one vital measurement
  WHERE o.composite_instability_score IS NOT NULL
)
SELECT
  group_label,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(1)] AS composite_instability_score_25th,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(2)] AS composite_instability_score_median,
  APPROX_QUANTILES(composite_instability_score, 4)[OFFSET(3)] AS composite_instability_score_75th,
  APPROX_QUANTILES(mean_abnormal_vital_burden, 4)[OFFSET(1)] AS mean_abnormal_vital_burden_25th,
  APPROX_QUANTILES(mean_abnormal_vital_burden, 4)[OFFSET(2)] AS mean_abnormal_vital_burden_median,
  APPROX_QUANTILES(mean_abnormal_vital_burden, 4)[OFFSET(3)] AS mean_abnormal_vital_burden_75th,
  APPROX_QUANTILES(los, 4)[OFFSET(1)] AS icu_los_25th,
  APPROX_QUANTILES(los, 4)[OFFSET(2)] AS icu_los_median,
  APPROX_QUANTILES(los, 4)[OFFSET(3)] AS icu_los_75th,
  AVG(los) AS mean_icu_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
FROM final
GROUP BY group_label
ORDER BY group_label;