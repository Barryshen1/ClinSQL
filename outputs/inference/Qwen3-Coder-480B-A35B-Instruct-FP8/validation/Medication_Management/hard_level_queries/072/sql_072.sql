WITH cohort AS (
  SELECT DISTINCT
    ie.subject_id,
    ie.hadm_id,
    ie.stay_id,
    ie.intime,
    ie.outtime,
    ie.los,
    adm.hospital_expire_flag,
    pat.anchor_age
  FROM
    physionet-data.mimiciv_3_1_icu.icustays ie
  JOIN
    physionet-data.mimiciv_3_1_hosp.admissions adm
    ON ie.hadm_id = adm.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.patients pat
    ON ie.subject_id = pat.subject_id
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
    AND ie.intime = (
      SELECT MIN(intime)
      FROM physionet-data.mimiciv_3_1_icu.icustays
      WHERE hadm_id = ie.hadm_id
    )
),

-- DKA diagnosis during ICU stay
dkas AS (
  SELECT DISTINCT
    cohort.subject_id,
    cohort.hadm_id,
    cohort.stay_id,
    cohort.los,
    cohort.hospital_expire_flag
  FROM
    cohort
  JOIN
    physionet-data.mimiciv_3_1_hosp.diagnoses_icd dx
    ON cohort.hadm_id = dx.hadm_id
  JOIN
    physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses d
    ON dx.icd_code = d.icd_code AND dx.icd_version = d.icd_version
  WHERE
    LOWER(d.long_title) LIKE '%ketoacidosis%'
),

-- Medications in first 48h of ICU stay
meds AS (
  SELECT DISTINCT
    cohort.stay_id,
    di.label AS med_name,
    di.itemid
  FROM
    cohort
  JOIN
    physionet-data.mimiciv_3_1_icu.inputevents iv
    ON cohort.stay_id = iv.stay_id
  JOIN
    physionet-data.mimiciv_3_1_icu.d_items di
    ON iv.itemid = di.itemid
  WHERE
    iv.starttime BETWEEN cohort.intime AND cohort.intime + INTERVAL 48 HOUR
    AND di.category IN ('Fluids/Intake', 'Medications', 'Antibiotics')
),

-- Medication complexity (count distinct meds)
med_complexity AS (
  SELECT
    stay_id,
    COUNT(DISTINCT itemid) AS med_count
  FROM
    meds
  GROUP BY
    stay_id
),

-- Hyperkalemia-risk drugs (example itemids or labels)
hyperkalemia_drugs AS (
  SELECT itemid
  FROM physionet-data.mimiciv_3_1_icu.d_items
  WHERE LOWER(label) IN (
    'spironolactone',
    'eplerenone',
    'lisinopril',
    'enalapril',
    'furosemide',
    'hydrochlorothiazide',
    'ibuprofen',
    'naproxen',
    'kcl',
    'potassium chloride'
  )
),

-- Patients with hyperkalemia-risk meds
patients_with_risk AS (
  SELECT DISTINCT
    meds.stay_id
  FROM
    meds
  JOIN
    hyperkalemia_drugs hkd
    ON meds.itemid = hkd.itemid
),

-- Final cohort with complexity and risk flag
final_cohort AS (
  SELECT
    c.stay_id,
    c.los,
    c.hospital_expire_flag,
    COALESCE(mc.med_count, 0) AS med_count,
    CASE WHEN pr.stay_id IS NOT NULL THEN 1 ELSE 0 END AS has_risk_drug
  FROM
    dkas c
  LEFT JOIN
    med_complexity mc
    ON c.stay_id = mc.stay_id
  LEFT JOIN
    patients_with_risk pr
    ON c.stay_id = pr.stay_id
),

-- Quartile of medication complexity
quartiles AS (
  SELECT
    *,
    NTILE(4) OVER (ORDER BY med_count) AS med_complexity_quartile
  FROM
    final_cohort
),

-- Aggregate stats
summary_stats AS (
  SELECT
    has_risk_drug,
    AVG(med_count) AS mean_med_count,
    APPROX_QUANTILES(med_count, 100)[OFFSET(50)] AS median_med_count,
    AVG(los) AS mean_los,
    AVG(hospital_expire_flag) AS mortality_rate
  FROM
    quartiles
  GROUP BY
    has_risk_drug
),

-- Top quartile outcomes
top_quartile_outcomes AS (
  SELECT
    has_risk_drug,
    AVG(los) AS mean_los_top_quartile,
    AVG(hospital_expire_flag) AS mortality_top_quartile
  FROM
    quartiles
  WHERE
    med_complexity_quartile = 4
  GROUP BY
    has_risk_drug
)

-- Final output
SELECT
  s.has_risk_drug,
  s.mean_med_count,
  s.median_med_count,
  s.mean_los,
  s.mortality_rate,
  t.mean_los_top_quartile,
  t.mortality_top_quartile
FROM
  summary_stats s
JOIN
  top_quartile_outcomes t
  ON s.has_risk_drug = t.has_risk_drug
ORDER BY
  s.has_risk_drug;