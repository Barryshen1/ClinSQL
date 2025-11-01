WITH cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age,
    p.gender,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime,
    a.discharge_location,
    DATE_DIFF(COALESCE(p.dod, a.dischtime), a.admittime, DAY) AS survival_days,
    CASE WHEN DATE_DIFF(COALESCE(p.dod, a.dischtime), a.admittime, DAY) <= 90 THEN 1 ELSE 0 END AS mortality_90d,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS hosp_los
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.icustays` i
    ON a.hadm_id = i.hadm_id
  WHERE p.anchor_age BETWEEN 70 AND 80
    AND p.gender = 'F'
),

-- Diagnoses for PE, AKI, ARDS
diagnosis_flags AS (
  SELECT
    hadm_id,
    MAX(CASE WHEN LOWER(di.long_title) LIKE '%pulmonary embolism%' THEN 1 ELSE 0 END) AS has_pe,
    MAX(CASE WHEN di.icd_code IN ('584.5','584.6','584.7','584.8','584.9') OR di.icd_code LIKE 'N17%' THEN 1 ELSE 0 END) AS has_aki,
    MAX(CASE WHEN di.icd_code IN ('518.5','518.82') OR di.icd_code = 'J80' THEN 1 ELSE 0 END) AS has_ards
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` di
    ON d.icd_code = di.icd_code AND d.icd_version = di.icd_version
  GROUP BY hadm_id
),

-- First creatinine in ICU within 24h as risk score
first_creatinine AS (
  SELECT
    c.hadm_id,
    MIN(c.valuenum) AS first_creat
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` c
  JOIN `physionet-data.mimiciv_3_1_icu.d_items` d
    ON c.itemid = d.itemid
  JOIN cohort co
    ON c.hadm_id = co.hadm_id
  WHERE LOWER(d.label) LIKE '%creatinine%'
    AND c.valuenum IS NOT NULL
    AND c.charttime BETWEEN co.icu_intime AND DATETIME_ADD(co.icu_intime, INTERVAL 24 HOUR)
  GROUP BY c.hadm_id
),

-- Final cohort with flags and risk score
final_cohort AS (
  SELECT
    co.*,
    df.has_pe,
    df.has_aki,
    df.has_ards,
    fc.first_creat,
    NTILE(5) OVER (ORDER BY fc.first_creat) AS risk_quintile
  FROM cohort co
  JOIN diagnosis_flags df
    ON co.hadm_id = df.hadm_id
  LEFT JOIN first_creatinine fc
    ON co.hadm_id = fc.hadm_id
  WHERE df.has_pe = 1
),

-- Overall 90-day mortality for 70–80 female inpatients
overall_mortality AS (
  SELECT
    AVG(CAST(mortality_90d AS FLOAT64)) AS overall_90d_mortality
  FROM final_cohort
)

-- Final aggregation by quintile
SELECT
  fc.risk_quintile,
  AVG(CAST(fc.mortality_90d AS FLOAT64)) AS mortality_90d,
  om.overall_90d_mortality AS general_90d_mortality,
  AVG(CAST(fc.has_aki AS FLOAT64)) AS aki_rate,
  AVG(CAST(fc.has_ards AS FLOAT64)) AS ards_rate,
  APPROX_QUANTILES(fc.hosp_los, 2)[OFFSET(1)] AS median_survivor_los
FROM final_cohort fc
CROSS JOIN overall_mortality om
WHERE fc.mortality_90d = 0 OR fc.hosp_los IS NOT NULL
GROUP BY fc.risk_quintile, om.overall_90d_mortality
ORDER BY fc.risk_quintile;