WITH 
  -- Identify stroke admissions
  stroke_admissions AS (
    SELECT 
      a.subject_id, 
      a.hadm_id, 
      a.admittime, 
      a.dischtime, 
      a.deathtime,
      p.anchor_age, 
      p.gender,
      CASE 
        WHEN ic.stay_id IS NOT NULL THEN 'ICU'
        ELSE 'Non-ICU'
      END AS care_type,
      TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM 
      `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN 
      `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
    LEFT JOIN 
      `physionet-data.mimiciv_3_1_icu.icustays` ic 
      ON a.hadm_id = ic.hadm_id
    WHERE 
      p.gender = 'F' 
      AND p.anchor_age BETWEEN 48 AND 58
      AND a.hadm_id IN (
        SELECT 
          hadm_id 
        FROM 
          `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` 
        WHERE 
          REGEXP_CONTAINS(icd_code, r'^430|431|432|433|434|435|436|437|438')  -- ICD-9 stroke codes
          OR REGEXP_CONTAINS(icd_code, r'^I60|I61|I62|I63|I64|I65|I66|I67|I68|I69')  -- ICD-10 stroke codes
      )
  ),
  
  -- Calculate in-hospital mortality
  mortality AS (
    SELECT 
      sa.care_type,
      CASE 
        WHEN sa.dischtime IS NULL AND sa.deathtime IS NOT NULL THEN 'Dead'
        ELSE 'Alive'
      END AS outcome,
      CASE 
        WHEN TIMESTAMP_DIFF(sa.dischtime, sa.admittime, DAY) <= 5 THEN 'LOS_≤5'
        ELSE 'LOS_>5'
      END AS los_category
    FROM 
      stroke_admissions sa
  )

SELECT 
  care_type,
  los_category,
  COUNT(CASE WHEN outcome = 'Dead' THEN 1 END) / COUNT(*) AS mortality_rate
FROM 
  mortality
GROUP BY 
  care_type, 
  los_category;