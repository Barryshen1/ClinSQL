WITH
-- Define DKA ICD codes
dka_icd_codes AS (
  SELECT DISTINCT icd_code
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE icd_code IN (
    'E13.10', 'E13.11', 'E11.10', 'E11.11', 'E10.10', 'E10.11',
    'E08.10', 'E08.11', 'E09.10', 'E09.11', 'E13.65', 'E11.65',
    'E10.65', 'E08.65', 'E09.65'
  )
),

-- Get male patients aged 59-69 with DKA
dka_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN dka_icd_codes dka ON d.icd_code = dka.icd_code
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.hospital_expire_flag IS NOT NULL
),

-- Get age-matched general inpatients (without DKA)
control_patients AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE
    p.gender = 'M'
    AND p.anchor_age BETWEEN 59 AND 69
    AND a.hospital_expire_flag IS NOT NULL
    AND a.hadm_id NOT IN (SELECT hadm_id FROM dka_patients)
),

-- Calculate SAPS-II score components
saps_ii_components AS (
  SELECT
    ce.subject_id,
    ce.hadm_id,
    MAX(CASE WHEN ce.itemid = 220045 THEN ce.valuenum ELSE NULL END) AS heart_rate,
    MAX(CASE WHEN ce.itemid = 220050 THEN ce.valuenum ELSE NULL END) AS systolic_bp,
    MAX(CASE WHEN ce.itemid = 220210 THEN ce.valuenum ELSE NULL END) AS temperature,
    MAX(CASE WHEN ce.itemid = 220224 THEN ce.valuenum ELSE NULL END) AS pao2_fio2,
    MAX(CASE WHEN ce.itemid = 220277 THEN ce.valuenum ELSE NULL END) AS urine_output,
    MAX(CASE WHEN ce.itemid = 220621 THEN ce.valuenum ELSE NULL END) AS serum_sodium,
    MAX(CASE WHEN ce.itemid = 220645 THEN ce.valuenum ELSE NULL END) AS serum_potassium,
    MAX(CASE WHEN ce.itemid = 220689 THEN ce.valuenum ELSE NULL END) AS serum_creatinine,
    MAX(CASE WHEN ce.itemid = 220739 THEN ce.valuenum ELSE NULL END) AS wbc,
    MAX(CASE WHEN ce.itemid = 220744 THEN ce.valuenum ELSE NULL END) AS gcs_total,
    MAX(CASE WHEN ce.itemid = 223900 THEN ce.valuenum ELSE NULL END) AS bilirubin,
    MAX(CASE WHEN ce.itemid = 223901 THEN ce.valuenum ELSE NULL END) AS glucose
  FROM `physionet-data.mimiciv_3_1_icu.chartevents` ce
  JOIN `physionet-data.mimiciv_3_1_icu.icustays` icu ON ce.subject_id = icu.subject_id AND ce.hadm_id = icu.hadm_id
  WHERE
    ce.charttime BETWEEN icu.intime AND TIMESTAMP_ADD(icu.intime, INTERVAL 24 HOUR)
    AND ce.valuenum IS NOT NULL
  GROUP BY ce.subject_id, ce.hadm_id
),

-- Calculate SAPS-II score
saps_ii_scores AS (
  SELECT
    s.subject_id,
    s.hadm_id,
    -- SAPS-II calculation (simplified version)
    (CASE
      WHEN s.heart_rate IS NULL THEN 0
      ELSE
        CASE
          WHEN s.heart_rate < 40 THEN 11
          WHEN s.heart_rate BETWEEN 40 AND 69 THEN 2
          WHEN s.heart_rate BETWEEN 70 AND 119 THEN 0
          WHEN s.heart_rate BETWEEN 120 AND 159 THEN 4
          WHEN s.heart_rate >= 160 THEN 7
          ELSE 0
        END
    END +
    CASE
      WHEN s.systolic_bp IS NULL THEN 0
      ELSE
        CASE
          WHEN s.systolic_bp < 70 THEN 13
          WHEN s.systolic_bp BETWEEN 70 AND 99 THEN 5
          WHEN s.systolic_bp BETWEEN 100 AND 199 THEN 0
          WHEN s.systolic_bp >= 200 THEN 2
          ELSE 0
        END
    END +
    CASE
      WHEN s.temperature IS NULL THEN 0
      ELSE
        CASE
          WHEN s.temperature < 36 THEN 3
          WHEN s.temperature BETWEEN 36 AND 38.4 THEN 0
          WHEN s.temperature >= 38.5 THEN 3
          ELSE 0
        END
    END +
    CASE
      WHEN s.pao2_fio2 IS NULL THEN 0
      ELSE
        CASE
          WHEN s.pao2_fio2 < 100 THEN 11
          WHEN s.pao2_fio2 BETWEEN 100 AND 199 THEN 9
          WHEN s.pao2_fio2 >= 200 THEN 6
          ELSE 0
        END
    END +
    CASE
      WHEN s.urine_output IS NULL THEN 0
      ELSE
        CASE
          WHEN s.urine_output < 500 THEN 11
          WHEN s.urine_output >= 500 THEN 0
          ELSE 0
        END
    END +
    CASE
      WHEN s.serum_sodium IS NULL THEN 0
      ELSE
        CASE
          WHEN s.serum_sodium < 125 THEN 5
          WHEN s.serum_sodium BETWEEN 125 AND 144 THEN 0
          WHEN s.serum_sodium >= 145 THEN 1
          ELSE 0
        END
    END +
    CASE
      WHEN s.serum_potassium IS NULL THEN 0
      ELSE
        CASE
          WHEN s.serum_potassium < 3 THEN 3
          WHEN s.serum_potassium BETWEEN 3 AND 4.9 THEN 0
          WHEN s.serum_potassium >= 5 THEN 3
          ELSE 0
        END
    END +
    CASE
      WHEN s.serum_creatinine IS NULL THEN 0
      ELSE
        CASE
          WHEN s.serum_creatinine < 0.6 THEN 0
          WHEN s.serum_creatinine BETWEEN 0.6 AND 1.4 THEN 0
          WHEN s.serum_creatinine >= 1.5 THEN 3
          ELSE 0
        END
    END +
    CASE
      WHEN s.wbc IS NULL THEN 0
      ELSE
        CASE
          WHEN s.wbc < 1 THEN 12
          WHEN s.wbc BETWEEN 1 AND 19.9 THEN 0
          WHEN s.wbc >= 20 THEN 3
          ELSE 0
        END
    END +
    CASE
      WHEN s.gcs_total IS NULL THEN 0
      ELSE
        CASE
          WHEN s.gcs_total >= 13 THEN 0
          WHEN s.gcs_total BETWEEN 10 AND 12 THEN 7
          WHEN s.gcs_total BETWEEN 7 AND 9 THEN 13
          WHEN s.gcs_total <= 6 THEN 26
          ELSE 0
        END
    END +
    CASE
      WHEN s.bilirubin IS NULL THEN 0
      ELSE
        CASE
          WHEN s.bilirubin < 4 THEN 0
          WHEN s.bilirubin >= 4 THEN 4
          ELSE 0
        END
    END +
    CASE
      WHEN s.glucose IS NULL THEN 0
      ELSE
        CASE
          WHEN s.glucose < 7.7 THEN 0
          WHEN s.glucose >= 7.8 THEN 4
          ELSE 0
        END
    END) AS saps_ii_score
  FROM saps_ii_components s
),

-- Identify AKI cases
aki_cases AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code
  WHERE
    d.icd_code IN (
      'N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9',
      'N18.0', 'N18.1', 'N18.2', 'N18.3', 'N18.4', 'N18.5', 'N18.6', 'N18.9'
    )
    AND d.icd_version = 10
),

-- Identify ARDS cases
ards_cases AS (
  SELECT DISTINCT
    d.subject_id,
    d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` diag ON d.icd_code = diag.icd_code
  WHERE
    d.icd_code IN (
      'J80', 'J80.0', 'J80.1', 'J80.2', 'J80.3', 'J80.4', 'J80.8', 'J80.9'
    )
    AND d.icd_version = 10
),

-- Combine all data for DKA patients
dka_results AS (
  SELECT
    dp.subject_id,
    dp.hadm_id,
    dp.anchor_age,
    dp.los_days,
    dp.hospital_expire_flag,
    TIMESTAMP_DIFF(dp.deathtime, dp.admittime, DAY) AS days_to_death,
    CASE WHEN TIMESTAMP_DIFF(dp.deathtime, dp.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS died_within_30_days,
    s.saps_ii_score,
    CASE WHEN ak.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
    CASE WHEN ar.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM dka_patients dp
  LEFT JOIN saps_ii_scores s ON dp.subject_id = s.subject_id AND dp.hadm_id = s.hadm_id
  LEFT JOIN aki_cases ak ON dp.subject_id = ak.subject_id AND dp.hadm_id = ak.hadm_id
  LEFT JOIN ards_cases ar ON dp.subject_id = ar.subject_id AND dp.hadm_id = ar.hadm_id
),

-- Combine all data for control patients
control_results AS (
  SELECT
    cp.subject_id,
    cp.hadm_id,
    cp.anchor_age,
    cp.los_days,
    cp.hospital_expire_flag,
    TIMESTAMP_DIFF(cp.deathtime, cp.admittime, DAY) AS days_to_death,
    CASE WHEN TIMESTAMP_DIFF(cp.deathtime, cp.admittime, DAY) <= 30 THEN 1 ELSE 0 END AS died_within_30_days,
    s.saps_ii_score,
    CASE WHEN ak.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_aki,
    CASE WHEN ar.subject_id IS NOT NULL THEN 1 ELSE 0 END AS has_ards
  FROM control_patients cp
  LEFT JOIN saps_ii_scores s ON cp.subject_id = s.subject_id AND cp.hadm_id = s.hadm_id
  LEFT JOIN aki_cases ak ON cp.subject_id = ak.subject_id AND cp.hadm_id = ak.hadm_id
  LEFT JOIN ards_cases ar ON cp.subject_id = ar.subject_id AND cp.hadm_id = ar.hadm_id
)

-- Final results
SELECT
  'DKA Patients' AS group,
  COUNT(*) AS patient_count,
  AVG(saps_ii_score) AS avg_saps_ii_score,
  SUM(died_within_30_days) * 100.0 / COUNT(*) AS pct_30day_mortality,
  SUM(has_aki) * 100.0 / COUNT(*) AS pct_with_aki,
  SUM(has_ards) * 100.0 / COUNT(*) AS pct_with_ards,
  AVG(los_days) AS avg_los_days
FROM dka_results
UNION ALL
SELECT
  'Control Patients' AS group,
  COUNT(*) AS patient_count,
  AVG(saps_ii_score) AS avg_saps_ii_score,
  SUM(died_within_30_days) * 100.0 / COUNT(*) AS pct_30day_mortality,
  SUM(has_aki) * 100.0 / COUNT(*) AS pct_with_aki,
  SUM(has_ards) * 100.0 / COUNT(*) AS pct_with_ards,
  AVG(los_days) AS avg_los_days
FROM control_results
ORDER BY group;