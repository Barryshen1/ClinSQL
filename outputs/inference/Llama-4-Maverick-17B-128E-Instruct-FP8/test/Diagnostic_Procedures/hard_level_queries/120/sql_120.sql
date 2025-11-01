WITH 
-- Step 1: Filter patients by age and gender
eligible_patients AS (
  SELECT subject_id
  FROM `physionet-data.mimiciv_3_1_hosp.patients`
  WHERE gender = 'M' AND anchor_age BETWEEN 74 AND 84
),

-- Step 2: Identify admissions with upper GI bleeding
ugi_bleeding_admissions AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` USING (icd_code, icd_version)
  WHERE LOWER(long_title) LIKE '%gastrointestinal hemorrhage%' OR LOWER(long_title) LIKE '%upper gi bleeding%'
),

-- Step 3: First ICU stay for eligible patients
first_icu_stay AS (
  SELECT icu.subject_id, icu.hadm_id, icu.stay_id, icu.intime
  FROM (
    SELECT subject_id, hadm_id, stay_id, intime,
           ROW_NUMBER() OVER (PARTITION BY hadm_id ORDER BY intime) as rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays`
  ) icu
  JOIN eligible_patients ON icu.subject_id = eligible_patients.subject_id
  JOIN ugi_bleeding_admissions ON icu.hadm_id = ugi_bleeding_admissions.hadm_id
  WHERE rn = 1
),

-- Step 4: Calculate diagnostic intensity
diagnostic_intensity AS (
  SELECT ce.stay_id, COUNT(*) as event_count
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN first_icu_stay fis ON ce.stay_id = fis.stay_id
  WHERE ce.charttime BETWEEN fis.intime AND TIMESTAMP_ADD(fis.intime, INTERVAL 3 DAY)
  GROUP BY ce.stay_id
),

-- Step 5: Stratify diagnostic intensity into quartiles
quartiles AS (
  SELECT stay_id, event_count,
         NTILE(4) OVER (ORDER BY event_count) as quartile
  FROM diagnostic_intensity
),

-- Step 6: Calculate required metrics per quartile
metrics AS (
  SELECT q.quartile,
         AVG(pe_cnt) as mean_procedure_count,
         AVG(hosp_los) as mean_hosp_los,
         AVG(hospital_expire_flag) as in_hospital_mortality
  FROM (
    SELECT q.stay_id, q.quartile,
           COALESCE(pe_cnt, 0) as pe_cnt,
           DATETIME_DIFF(a.dischtime, a.admittime, DAY) as hosp_los,
           a.hospital_expire_flag
    FROM quartiles q
    JOIN first_icu_stay fis ON q.stay_id = fis.stay_id
    JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON fis.hadm_id = a.hadm_id
    LEFT JOIN (
      SELECT stay_id, COUNT(*) as pe_cnt
      FROM `physionet-data.mimiciv_3_1_icu.procedureevents`
      GROUP BY stay_id
    ) pe ON q.stay_id = pe.stay_id
  ) sub
  GROUP BY quartile
)

SELECT * FROM metrics ORDER BY quartile;