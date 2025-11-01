WITH first_icu_stay AS (
  SELECT 
    subject_id,
    hadm_id,
    stay_id,
    intime,
    los,
    gender,
    anchor_age,
    anchor_year,
    age_at_admission
  FROM (
    SELECT 
      icu.subject_id,
      icu.hadm_id,
      icu.stay_id,
      icu.intime,
      icu.los,
      p.gender,
      p.anchor_age,
      p.anchor_year,
      p.anchor_age + (EXTRACT(YEAR FROM icu.intime) - p.anchor_year) AS age_at_admission,
      ROW_NUMBER() OVER (PARTITION BY icu.subject_id ORDER BY icu.intime) AS rn
    FROM `physionet-data.mimiciv_3_1_icu.icustays` icu
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
      ON icu.subject_id = p.subject_id
  )
  WHERE rn = 1
),
hepatic_failure AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code 
    AND d.icd_version = dd.icd_version
  WHERE 
    dd.long_title LIKE '%hepatic failure%' 
    OR dd.long_title LIKE '%liver failure%'
),
cohort AS (
  SELECT 
    fis.subject_id,
    fis.hadm_id,
    fis.stay_id,
    fis.intime,
    fis.los
  FROM first_icu_stay fis
  INNER JOIN hepatic_failure hf
    ON fis.subject_id = hf.subject_id 
    AND fis.hadm_id = hf.hadm_id
  WHERE 
    fis.gender = 'M'
    AND fis.age_at_admission BETWEEN 90 AND 100
),
procedure_counts AS (
  SELECT 
    c.subject_id,
    c.hadm_id,
    c.stay_id,
    c.los,
    COUNT(DISTINCT pe.itemid) AS procedure_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_icu.procedureevents` pe
    ON c.subject_id = pe.subject_id
    AND c.hadm_id = pe.hadm_id
    AND c.stay_id = pe.stay_id
    AND pe.starttime >= c.intime
    AND pe.starttime <= c.intime + INTERVAL '72' HOUR
    AND pe.ordercategoryname = 'Diagnostic'
  GROUP BY c.subject_id, c.hadm_id, c.stay_id, c.los
),
quartiles AS (
  SELECT 
    *,
    NTILE(4) OVER (ORDER BY procedure_count) AS quartile
  FROM procedure_counts
)
SELECT 
  quartile,
  COUNT(*) AS num_patients,
  MIN(procedure_count) AS min_procedures,
  MAX(procedure_count) AS max_procedures,
  AVG(procedure_count) AS mean_procedures,
  AVG(los) AS mean_los_days,
  AVG(a.hospital_expire_flag) * 100 AS mortality_percent
FROM quartiles q
INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
  ON q.hadm_id = a.hadm_id
GROUP BY quartile
ORDER BY quartile;