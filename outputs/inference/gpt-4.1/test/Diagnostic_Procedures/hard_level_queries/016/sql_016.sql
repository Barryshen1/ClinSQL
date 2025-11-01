WITH pneumonia_patients AS (
  -- Get first ICU stay for male patients aged 88-98 with pneumonia
  SELECT
    p.subject_id,
    p.anchor_age,
    p.gender,
    a.hadm_id,
    i.stay_id,
    i.intime,
    i.outtime,
    i.los,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  JOIN (
    SELECT
      subject_id,
      hadm_id,
      stay_id,
      intime,
      outtime,
      los,
      ROW_NUMBER() OVER (PARTITION BY subject_id ORDER BY intime) AS rn
    FROM physionet-data.mimiciv_3_1_icu.icustays
  ) i
    ON p.subject_id = i.subject_id AND a.hadm_id = i.hadm_id
  -- Only first ICU stay
  WHERE i.rn = 1
    AND p.gender = 'M'
    AND p.anchor_age BETWEEN 88 AND 98
    AND EXISTS (
      SELECT 1
      FROM physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
      JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dd
        ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
      WHERE d.subject_id = p.subject_id
        AND d.hadm_id = a.hadm_id
        AND (
          -- ICD-10 pneumonia: J12-J18
          (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^J1[2-8]'))
          -- ICD-9 pneumonia: 480-486, only if icd_code is numeric
          OR (
            d.icd_version = 9
            AND SAFE_CAST(d.icd_code AS INT64) IS NOT NULL
            AND SAFE_CAST(d.icd_code AS INT64) BETWEEN 480 AND 486
          )
        )
    )
),

diagnostic_procedure_counts AS (
  -- Count diagnostic procedures in first 72h of ICU stay
  SELECT
    pp.subject_id,
    pp.hadm_id,
    pp.stay_id,
    pp.intime,
    pp.outtime,
    pp.los,
    pp.hospital_expire_flag,
    COUNT(DISTINCT pr.seq_num) AS procedure_count
  FROM pneumonia_patients pp
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.procedures_icd pr
    ON pp.subject_id = pr.subject_id
    AND pp.hadm_id = pr.hadm_id
    AND pr.chartdate >= pp.intime
    AND pr.chartdate < DATETIME_ADD(pp.intime, INTERVAL 72 HOUR)
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.d_icd_procedures dp
    ON pr.icd_code = dp.icd_code AND pr.icd_version = dp.icd_version
    -- Only diagnostic procedures (long_title contains 'diagnos')
    AND LOWER(dp.long_title) LIKE '%diagnos%'
  GROUP BY
    pp.subject_id, pp.hadm_id, pp.stay_id, pp.intime, pp.outtime, pp.los, pp.hospital_expire_flag
),

quintiles AS (
  -- Assign quintiles based on procedure_count
  SELECT
    *,
    NTILE(5) OVER (ORDER BY procedure_count) AS procedure_quintile
  FROM diagnostic_procedure_counts
)

SELECT
  procedure_quintile,
  COUNT(*) AS n_patients,
  ROUND(AVG(procedure_count),2) AS avg_procedure_count,
  ROUND(AVG(los),2) AS avg_icu_los_days,
  ROUND(100 * AVG(CAST(hospital_expire_flag AS FLOAT64)),2) AS in_hospital_mortality_percent
FROM quintiles
GROUP BY procedure_quintile
ORDER BY procedure_quintile;