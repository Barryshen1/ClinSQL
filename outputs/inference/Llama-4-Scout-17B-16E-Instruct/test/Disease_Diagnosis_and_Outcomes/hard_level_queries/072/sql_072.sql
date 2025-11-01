WITH 
-- Target population: Female patients aged 67-77 with ACS and ICU stay
target_population AS (
  SELECT 
    a.subject_id, 
    a.hadm_id, 
    i.stay_id,
    p.anchor_age,
    p.gender,
    a.admittime,
    a.dischtime,
    a.deathtime
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p 
      ON a.subject_id = p.subject_id
  JOIN 
    `physionet-data.mimiciv_3_1_icu.icustays` i 
      ON a.hadm_id = i.hadm_id
  WHERE 
    p.gender = 'F' 
    AND p.anchor_age BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        d.hadm_id = a.hadm_id
        AND (d.icd_code LIKE '410%' OR d.icd_code LIKE 'I24%')  -- ACS
    )
),

-- 30-day mortality
mortality AS (
  SELECT 
    subject_id,
    hadm_id,
    CASE 
      WHEN deathtime IS NOT NULL AND deathtime <= (admittime + INTERVAL 30 DAY) THEN 1
      ELSE 0
    END AS thirty_day_mortality
  FROM 
    target_population
)

-- Calculate mean risk score and 30-day mortality
SELECT 
  AVG(m.thirty_day_mortality) AS mean_thirty_day_mortality
FROM 
  mortality m;