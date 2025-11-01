WITH dapt_admissions AS (
  -- Identify admissions where both aspirin and clopidogrel were prescribed
  SELECT hadm_id
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE LOWER(drug) IN ('aspirin', 'clopidogrel')
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT LOWER(drug)) = 2
),
first_icu_stays AS (
  -- Get first ICU stay for each patient
  SELECT *,
         ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
  FROM physionet-data.mimiciv_3_1_icu.icustays
)
SELECT 
  AVG(icu.los) AS avg_icu_los_days
FROM first_icu_stays icu
JOIN physionet-data.mimiciv_3_1_hosp.patients pat
  ON icu.subject_id = pat.subject_id
JOIN dapt_admissions dapt
  ON icu.hadm_id = dapt.hadm_id
WHERE icu.rn = 1
  AND pat.gender = 'M'
  AND pat.anchor_age BETWEEN 76 AND 86;