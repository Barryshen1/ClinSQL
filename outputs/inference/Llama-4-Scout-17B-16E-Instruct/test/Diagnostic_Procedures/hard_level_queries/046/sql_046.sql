WITH 
  -- Identify ARDS patients
  ards_patients AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      ic.stay_id
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
        ON a.hadm_id = ic.hadm_id
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        ON a.hadm_id = d.hadm_id
    WHERE 
      d.icd_code LIKE 'J84.1'  -- ARDS ICD code
      AND a.gender = 'F'
      AND a.anchor_age BETWEEN 37 AND 47
  ),

  -- First ICU stay for each patient
  first_icu_stay AS (
    SELECT 
      subject_id, 
      hadm_id, 
      stay_id,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays`
  ),

  -- Procedures within first 72 hours of ICU stay
  procedures_72hrs AS (
    SELECT 
      ic.stay_id, 
      COUNT(DISTINCT pe.itemid) AS num_procedures
    FROM 
      `physionet-data.mimiciv_3_1_icu.icustays` ic
    JOIN 
      `physionet-data.mimiciv_3_1_icu.procedureevents` pe 
        ON ic.stay_id = pe.stay_id
    WHERE 
      pe.starttime BETWEEN ic.intime AND TIMESTAMP_ADD(ic.intime, INTERVAL 72 HOUR)
    GROUP BY 
      ic.stay_id
  ),

  -- Hospital LOS and mortality
  hospital_outcomes AS (
    SELECT 
      a.hadm_id, 
      TIMESTAMPDIFF(DAY, a.admittime, COALESCE(a.dischtime, a.deathtime)) AS los,
      IF(a.deathtime IS NOT NULL, 1, 0) AS mortality
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
  )

-- Target population and outcomes
SELECT 
  'Target' AS population,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.num_procedures) AS p75_procedures,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.num_procedures) AS p90_procedures,
  AVG(h.los) AS mean_los,
  AVG(h.mortality) AS mortality
FROM 
  ards_patients ap
JOIN 
  first_icu_stay fics ON ap.subject_id = fics.subject_id AND ap.hadm_id = fics.hadm_id AND ap.stay_id = fics.stay_id AND fics.rn = 1
JOIN 
  procedures_72hrs p ON fics.stay_id = p.stay_id
JOIN 
  hospital_outcomes h ON ap.hadm_id = h.hadm_id

UNION ALL

-- All ICU patients and outcomes
SELECT 
  'All ICU' AS population,
  PERCENTILE_CONT(0.75) WITHIN GROUP (ORDER BY p.num_procedures) AS p75_procedures,
  PERCENTILE_CONT(0.9) WITHIN GROUP (ORDER BY p.num_procedures) AS p90_procedures,
  AVG(h.los) AS mean_los,
  AVG(h.mortality) AS mortality
FROM 
  first_icu_stay fics
JOIN 
  procedures_72hrs p ON fics.stay_id = p.stay_id
JOIN 
  hospital_outcomes h ON fics.hadm_id = h.hadm_id;