WITH hepatic_cohort AS (
  SELECT DISTINCT
    icu.subject_id,
    icu.hadm_id,
    icu.stay_id,
    icu.intime,
    icu.outtime,
    icu.los AS icu_los,
    adm.hospital_expire_flag
  FROM
    physionet-data.mimiciv_3_1_icu.icustays icu
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON icu.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON icu.subject_id = pat.subject_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON icu.hadm_id = dx.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d_dx
    ON dx.icd_code = d_dx.icd_code AND dx.icd_version = d_dx.icd_version
  WHERE
    pat.gender = 'M'
    AND pat.anchor_age BETWEEN 75 AND 85
    AND LOWER(d_dx.long_title) LIKE '%hepatic failure%'
),

-- Vasopressor use in first 48 hours as instability proxy
vasopressor_use AS (
  SELECT
    he.stay_id,
    MAX(ie.amount) AS max_vasopressor_dose
  FROM
    hepatic_cohort he
  JOIN
    physionet-data.mimiciv_3_1_icu.inputevents ie
    ON he.stay_id = ie.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON ie.itemid = di.itemid
  WHERE
    LOWER(di.label) IN ('norepinephrine', 'epinephrine', 'dopamine', 'vasopressin')
    AND ie.starttime BETWEEN he.intime AND DATETIME_ADD(he.intime, INTERVAL 48 HOUR)
  GROUP BY
    he.stay_id
),

-- Labs in first 48 hours for hepatic cohort
hepatic_labs AS (
  SELECT
    he.stay_id,
    COUNT(CASE WHEN LOWER(di.label) = 'bilirubin' THEN 1 END) AS bilirubin_count,
    COUNT(CASE WHEN LOWER(di.label) = 'creatinine' THEN 1 END) AS creatinine_count,
    COUNT(CASE WHEN LOWER(di.label) = 'inr' THEN 1 END) AS inr_count,
    COUNT(CASE WHEN LOWER(di.label) = 'platelets' THEN 1 END) AS platelet_count
  FROM
    hepatic_cohort he
  JOIN
    physionet-data.mimiciv_3_1_hosp.labevents le
    ON he.hadm_id = le.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems di
    ON le.itemid = di.itemid
  WHERE
    le.charttime BETWEEN he.intime AND DATETIME_ADD(he.intime, INTERVAL 48 HOUR)
    AND LOWER(di.label) IN ('bilirubin', 'creatinine', 'inr', 'platelets')
  GROUP BY
    he.stay_id
),

-- General inpatient lab frequencies (scalar aggregate)
general_labs AS (
  SELECT
    COUNT(CASE WHEN LOWER(di.label) = 'bilirubin' THEN 1 END) AS bilirubin_count,
    COUNT(CASE WHEN LOWER(di.label) = 'creatinine' THEN 1 END) AS creatinine_count,
    COUNT(CASE WHEN LOWER(di.label) = 'inr' THEN 1 END) AS inr_count,
    COUNT(CASE WHEN LOWER(di.label) = 'platelets' THEN 1 END) AS platelet_count
  FROM
    physionet-data.mimiciv_3_1_hosp.labevents le
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_labitems di
    ON le.itemid = di.itemid
  WHERE
    le.charttime IS NOT NULL
    AND LOWER(di.label) IN ('bilirubin', 'creatinine', 'inr', 'platelets')
)

-- Final aggregation
SELECT
  MAX(COALESCE(v.max_vasopressor_dose, 0)) AS max_instability_score,
  AVG(he.hospital_expire_flag) AS mortality_rate,
  AVG(he.icu_los) AS avg_icu_los,
  SUM(hl.bilirubin_count) AS hepatic_bilirubin_count,
  SUM(hl.creatinine_count) AS hepatic_creatinine_count,
  SUM(hl.inr_count) AS hepatic_inr_count,
  SUM(hl.platelet_count) AS hepatic_platelet_count,
  (SELECT bilirubin_count FROM general_labs) AS general_bilirubin_count,
  (SELECT creatinine_count FROM general_labs) AS general_creatinine_count,
  (SELECT inr_count FROM general_labs) AS general_inr_count,
  (SELECT platelet_count FROM general_labs) AS general_platelet_count
FROM
  hepatic_cohort he
LEFT JOIN
  vasopressor_use v
  ON he.stay_id = v.stay_id
LEFT JOIN
  hepatic_labs hl
  ON he.stay_id = hl.stay_id;