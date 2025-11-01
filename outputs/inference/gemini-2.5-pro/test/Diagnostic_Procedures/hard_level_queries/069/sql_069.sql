WITH
  pe_admissions AS (
    -- Step 1: Identify male patients aged 44-54 with a Pulmonary Embolism (PE) diagnosis.
    SELECT
      pat.subject_id,
      adm.hadm_id,
      adm.admittime,
      adm.dischtime,
      adm.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.patients` AS pat
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.admissions` AS adm
      ON pat.subject_id = adm.subject_id
    WHERE
      pat.gender = 'M'
      AND (
        pat.anchor_age + EXTRACT(YEAR FROM adm.admittime) - pat.anchor_year
      ) BETWEEN 44 AND 54
      AND adm.hadm_id IN (
        SELECT DISTINCT
          hadm_id
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
        WHERE
          -- ICD-10 codes for Pulmonary Embolism
          icd_code LIKE 'I26%'
          -- ICD-9 codes for Pulmonary Embolism
          OR icd_code LIKE '4151%'
      )
  ),
  first_icu_stays AS (
    -- Step 2: For the above cohort, find their first ICU stay for each admission.
    SELECT
      pea.subject_id,
      pea.hadm_id,
      icu.stay_id,
      pea.admittime,
      pea.dischtime,
      pea.hospital_expire_flag,
      icu.intime AS icu_intime
    FROM pe_admissions AS pea
    INNER JOIN
      `physionet-data.mimiciv_3_1_icu.icustays` AS icu
      ON pea.hadm_id = icu.hadm_id
    QUALIFY ROW_NUMBER() OVER (PARTITION BY pea.hadm_id ORDER BY icu.intime) = 1
  ),
  procedures_in_window AS (
    -- Step 3: Count distinct procedures within the first 72 hours of the ICU stay.
    SELECT
      f.stay_id,
      COUNT(DISTINCT proc.icd_code) AS procedure_count
    FROM first_icu_stays AS f
    INNER JOIN
      `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS proc
      ON f.hadm_id = proc.hadm_id
    WHERE
      proc.chartdate BETWEEN f.icu_intime AND DATETIME_ADD(
        f.icu_intime,
        INTERVAL 72 HOUR
      )
    GROUP BY
      f.stay_id
  ),
  patient_stats_with_quintiles AS (
    -- Step 4: Combine stats and stratify patients into quintiles based on procedure count.
    SELECT
      f.stay_id,
      COALESCE(p.procedure_count, 0) AS procedure_count,
      DATETIME_DIFF(f.dischtime, f.admittime, DAY) AS hospital_los_days,
      f.hospital_expire_flag,
      NTILE(5) OVER (ORDER BY COALESCE(p.procedure_count, 0)) AS procedure_quintile
    FROM first_icu_stays AS f
    LEFT JOIN
      procedures_in_window AS p
      ON f.stay_id = p.stay_id
  )
-- Step 5: Aggregate metrics per quintile.
SELECT
  s.procedure_quintile,
  AVG(s.procedure_count) AS avg_procedure_count,
  AVG(s.hospital_los_days) AS avg_hospital_los_days,
  AVG(CAST(s.hospital_expire_flag AS FLOAT64)) * 100 AS mortality_percentage
FROM patient_stats_with_quintiles AS s
GROUP BY
  s.procedure_quintile
ORDER BY
  s.procedure_quintile;