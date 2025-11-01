WITH first_adm AS (
  SELECT a.subject_id, a.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  QUALIFY ROW_NUMBER() OVER (PARTITION BY a.subject_id ORDER BY a.admittime) = 1
),

-- Step 2: detect DAPT (aspirin + second antiplatelet) during that admission
-- We search both prescriptions and pharmacy tables for aspirin and for second antiplatelets.
dap AS (
  SELECT subject_id, hadm_id
  FROM (
    -- aspirin presence
    SELECT subject_id, hadm_id, 1 AS kind_asp
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE LOWER(drug) LIKE '%aspirin%'
    UNION ALL
    SELECT subject_id, hadm_id, 1 AS kind_asp
    FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
    WHERE LOWER(medication) LIKE '%aspirin%'
    -- second antiplatelet presence
    UNION ALL
    SELECT subject_id, hadm_id, 0 AS kind_asp
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
    WHERE LOWER(drug) LIKE '%clopidogrel%'
       OR LOWER(drug) LIKE '%prasugrel%'
       OR LOWER(drug) LIKE '%ticagrelor%'
       OR LOWER(drug) LIKE '%ticlopidine%'
    UNION ALL
    SELECT subject_id, hadm_id, 0 AS kind_asp
    FROM `physionet-data.mimiciv_3_1_hosp.pharmacy`
    WHERE LOWER(medication) LIKE '%clopidogrel%'
       OR LOWER(medication) LIKE '%prasugrel%'
       OR LOWER(medication) LIKE '%ticagrelor%'
       OR LOWER(medication) LIKE '%ticlopidine%'
  ) t
  GROUP BY subject_id, hadm_id
  -- require at least one aspirin and at least one second antipletelet
  HAVING SUM(CASE WHEN kind_asp = 1 THEN 1 ELSE 0 END) > 0
     AND SUM(CASE WHEN kind_asp = 0 THEN 1 ELSE 0 END) > 0
),

-- Step 3: eligible admissions are first admissions with DAPT and male aged 76-86
eligible AS (
  SELECT f.subject_id, f.hadm_id
  FROM first_adm f
  JOIN dap d ON f.subject_id = d.subject_id AND f.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON p.subject_id = f.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 76 AND 86
),

-- Step 4: determine the first ICU stay per hadm_id
first_icu AS (
  SELECT hadm_id, MIN(intime) AS first_intime
  FROM `physionet-data.mimiciv_3_1_icu.icustays`
  GROUP BY hadm_id
)

-- Step 5: compute average ICU LOS (days) for the first ICU stay of eligible admissions
SELECT AVG(icu.los / 24.0) AS avg_icu_los_days
FROM eligible e
JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu
  ON icu.hadm_id = e.hadm_id
JOIN first_icu fi
  ON fi.hadm_id = icu.hadm_id AND fi.first_intime = icu.intime;