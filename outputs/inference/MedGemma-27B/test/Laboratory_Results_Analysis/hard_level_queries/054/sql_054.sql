WITH AMI_Patients AS (
  SELECT
    p.subject_id,
    p.gender,
    p.anchor_age,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    d.icd_code,
    d.icd_version
  FROM
    `physionet-data.mimiciv_3_1_hosp.patients` AS p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` AS a ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS d ON a.hadm_id = d.hadm_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 38 AND 48
    AND d.icd_code LIKE 'I21%' -- AMI codes
),
CriticalLabs AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    itemid,
    valuenum,
    valueuom
  FROM
    `physionet-data.mimiciv_3_1_hosp.labevents`
  WHERE
    itemid IN (
      SELECT
        itemid
      FROM
        `physionet-data.mimiciv_3_1_hosp.d_labitems`
      WHERE
        category = 'Laboratory'
        AND label IN (
          'Potassium', 'Sodium', 'Chloride', 'Bicarbonate', 'BUN', 'Creatinine', 'Glucose', 'Calcium', 'Magnesium', 'Phosphate', 'Troponin I', 'Troponin T', 'CK-MB', 'Hemoglobin', 'Platelet Count', 'White Blood Cell Count'
        )
    )
),
LabInstabilityScore AS (
  SELECT
    subject_id,
    hadm_id,
    charttime,
    CASE
      WHEN valuenum < 3.5 OR valuenum > 5.0 THEN 1
      ELSE 0
    END AS potassium_instability,
    CASE
      WHEN valuenum < 135 OR valuenum > 145 THEN 1
      ELSE 0
    END AS sodium_instability,
    CASE
      WHEN valuenum < 98 OR valuenum > 107 THEN 1
      ELSE 0
    END AS chloride_instability,
    CASE
      WHEN valuenum < 22 OR valuenum > 29 THEN 1
      ELSE 0
    END AS bicarbonate_instability,
    CASE
      WHEN valuenum < 7 OR valuenum > 20 THEN 1
      ELSE 0
    END AS bun_instability,
    CASE
      WHEN valuenum < 0.6 OR valuenum > 1.2 THEN 1
      ELSE 0
    END AS creatinine_instability,
    CASE
      WHEN valuenum < 70 OR valuenum > 100 THEN 1
      ELSE 0
    END AS glucose_instability,
    CASE
      WHEN valuenum < 8.5 OR valuenum > 10.5 THEN 1
      ELSE 0
    END AS calcium_instability,
    CASE
      WHEN valuenum < 1.5 OR valuenum > 2.5 THEN 1
      ELSE 0
    END AS magnesium_instability,
    CASE
      WHEN valuenum < 2.5 OR valuenum > 4.5 THEN 1
      ELSE 0
    END AS phosphate_instability,
    CASE
      WHEN valuenum > 0.04 THEN 1
      ELSE 0
    END AS troponin_i_instability,
    CASE
      WHEN valuenum > 0.01 THEN 1
      ELSE 0
    END AS troponin_t_instability,
    CASE
      WHEN valuenum > 25 THEN 1
      ELSE 0
    END AS ck_mb_instability,
    CASE
      WHEN valuenum < 12 OR valuenum > 16 THEN 1
      ELSE 0
    END AS hemoglobin_instability,;