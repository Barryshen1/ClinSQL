WITH PatientCohort AS (
  -- Select patients matching the criteria: 42-year-old man, postoperative ICU admission, age 37-47
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.hadm_id,
    a.admission_type,
    i.stay_id,
    i.intime AS icu_intime,
    i.outtime AS icu_outtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` AS p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` AS i
    ON a.hadm_id = i.hadm_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age = 42
    AND p.anchor_age BETWEEN 37 AND 47
    AND a.admission_type = 'ELECTIVE' -- Assuming 'ELECTIVE' implies postoperative
    AND i.stay_id IS NOT NULL -- Ensure it's an ICU admission
),
MedicationComplexity AS (
  -- Calculate medication complexity for each patient in the cohort over the first 72 hours of ICU stay
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.icu_intime,
    COUNT(DISTINCT CASE
      WHEN pharmacy.drug_type = 'Drug' THEN pharmacy.drug
    END) AS unique_meds,
    COUNT(DISTINCT CASE
      WHEN pharmacy.drug_type = 'Drug' THEN pharmacy.route
    END) AS unique_routes,
    COUNT(DISTINCT CASE
      WHEN pharmacy.drug_type = 'Drug' THEN pharmacy.frequency
    END) AS unique_frequencies
  FROM PatientCohort AS pc
  JOIN `physionet-data.mimiciv_3_1_icu.pharmacy` AS pharmacy
    ON pc.hadm_id = pharmacy.hadm_id
  WHERE
    pharmacy.starttime >= pc.icu_intime
    AND pharmacy.starttime < DATE_ADD(pc.icu_intime, INTERVAL 72 HOUR)
    AND pharmacy.drug_type = 'Drug' -- Focus on medications
  GROUP BY
    pc.subject_id,
    pc.hadm_id,
    pc.stay_id,
    pc.icu_intime
),
ComplexityScore AS (
  -- Combine complexity metrics into a single score
  SELECT
    mc.subject_id,
    mc.hadm_id,
    mc.stay_id,
    mc.icu_intime,
    mc.unique_meds + mc.unique_routes + mc.unique_frequencies AS complexity_score
  FROM MedicationComplexity AS mc
),
Quintiles AS (
  -- Assign patients to complexity quintiles based on their score
  SELECT
    cs.subject_id,
    cs.hadm_id,
    cs.stay_id,
    cs.icu_intime,
    cs.complexity_score,
    NTILE(5) OVER (ORDER BY cs.complexity_score) AS complexity_quintile
  FROM ComplexityScore AS cs
),
OutcomeAnalysis AS (
  -- Calculate LOS, mortality, and readmission rates per quintile
  SELECT
    q.complexity_quintile,
    q.complexity_score,
    AVG(a.los) AS avg_los,
    AVG(CASE WHEN a.hospital_expire_flag = TRUE THEN 1 ELSE 0 END) AS mortality_rate,
    AVG(CASE WHEN r.readmitted = TRUE THEN 1 ELSE 0 END) AS readmission_rate
  FROM Quintiles AS q
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    ON q.hadm_id = a.hadm_id
  LEFT JOIN (
    SELECT
      a.hadm_id,
      TRUE AS readmitted
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
    WHERE
      a.admittime > DATE_ADD(
        (
          SELECT
            a2;