WITH
-- Get relevant patient admissions
patient_admissions AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    p.gender,
    p.anchor_age,
    p.anchor_year,
    a.hospital_expire_flag
  FROM
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN
    `physionet-data.mimiciv_3_1_hosp.patients` p
  ON
    a.subject_id = p.subject_id
  WHERE
    p.gender = 'F'
    AND p.anchor_age BETWEEN 60 AND 70
    AND a.hospital_expire_flag = 0
),

-- Get patients with T2DM and HF
patients_with_conditions AS (
  SELECT DISTINCT
    pa.subject_id,
    pa.hadm_id,
    pa.admittime,
    pa.dischtime
  FROM
    patient_admissions pa
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_t2dm
  ON
    di_t2dm.subject_id = pa.subject_id AND di_t2dm.hadm_id = pa.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_hf
  ON
    di_hf.subject_id = pa.subject_id AND di_hf.hadm_id = pa.hadm_id
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd_t2dm
  ON
    di_t2dm.icd_code = dicd_t2dm.icd_code AND di_t2dm.icd_version = dicd_t2dm.icd_version
  JOIN
    `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd_hf
  ON
    di_hf.icd_code = dicd_hf.icd_code AND di_hf.icd_version = dicd_hf.icd_version
  WHERE
    (
      -- T2DM codes
      (di_t2dm.icd_code LIKE 'E11%' AND di_t2dm.icd_version = 10)
      OR (di_t2dm.icd_code LIKE '250%' AND di_t2dm.icd_version = 9)
    )
    AND
    (
      -- HF codes
      (di_hf.icd_code LIKE 'I50%' AND di_hf.icd_version = 10)
      OR (di_hf.icd_code LIKE '428%' AND di_hf.icd_version = 9)
    )
),

-- Get medication classes
medication_classes AS (
  SELECT
    p.subject_id,
    p.hadm_id,
    p.starttime,
    p.drug,
    CASE
      WHEN p.drug IN ('METFORMIN', 'GLIPIZIDE', 'GLYBURIDE', 'INSULIN', 'PIOGLITAZONE', 'ROSIGLITAZONE', 'SITAGLIPTIN', 'SAXAGLIPTIN', 'LINAGLIPTIN', 'ALOGLIPTIN', 'CANAGLIFLOZIN', 'DAPAGLIFLOZIN', 'EMPAGLIFLOZIN', 'ERTUGLIFLOZIN') THEN 'Antidiabetic'
      WHEN p.drug IN ('METOPROLOL', 'CARVEDILOL', 'BISOPROLOL', 'ATENOLOL', 'NADOLOL', 'PROPRANOLOL', 'TIMOLOL') THEN 'Beta-blocker'
      WHEN p.drug IN ('LISINOPRIL', 'ENALAPRIL', 'RAMIPRIL', 'BENZEPRIL', 'QUINAPRIL', 'FOSINOPRIL', 'PERINDOPRIL', 'TRANDOLAPRIL', 'MOEXIPRIL', 'LOSARTAN', 'VALSARTAN', 'IRBESARTAN', 'CANDESARTAN', 'TELMISARTAN', 'OLMESARTAN', 'AZILSARTAN', 'SACUBITRIL/VALSARTAN') THEN 'ACEi/ARB/ARNI'
      WHEN p.drug IN ('FUROSEMIDE', 'BUMETANIDE', 'TORSEMIDE', 'ETHACRYNIC ACID') THEN 'Loop diuretic'
      ELSE NULL
    END AS medication_class
  FROM
    `physionet-data.mimiciv_3_1_hosp.prescriptions` p
  WHERE
    p.drug IS NOT NULL
),

-- Get first 48 hours medications
first_48h_meds AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    mc.medication_class,
    COUNT(DISTINCT mc.medication_class) AS count
  FROM
    patients_with_conditions pc
  JOIN
    medication_classes mc
  ON
    pc.subject_id = mc.subject_id AND pc.hadm_id = mc.hadm_id
  WHERE
    mc.starttime BETWEEN pc.admittime AND TIMESTAMP_ADD(pc.admittime, INTERVAL 48 HOUR)
  GROUP BY
    pc.subject_id, pc.hadm_id, mc.medication_class
),

-- Get final 24 hours medications
final_24h_meds AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    mc.medication_class,
    COUNT(DISTINCT mc.medication_class) AS count
  FROM
    patients_with_conditions pc
  JOIN
    medication_classes mc
  ON
    pc.subject_id = mc.subject_id AND pc.hadm_id = mc.hadm_id
  WHERE
    mc.starttime BETWEEN TIMESTAMP_SUB(pc.dischtime, INTERVAL 24 HOUR) AND pc.dischtime
  GROUP BY
    pc.subject_id, pc.hadm_id, mc.medication_class
),

-- Count patients with each medication class in each time window
med_counts AS (
  SELECT
    medication_class,
    COUNT(DISTINCT subject_id) AS first_48h_count,
    0 AS final_24h_count
  FROM
    first_48h_meds
  GROUP BY
    medication_class

  UNION ALL

  SELECT
    medication_class,
    0 AS first_48h_count,
    COUNT(DISTINCT subject_id) AS final_24h_count
  FROM
    final_24h_meds
  GROUP BY
    medication_class
),

-- Aggregate counts
aggregated_counts AS (
  SELECT
    medication_class,
    SUM(first_48h_count) AS first_48h_count,
    SUM(final_24h_count) AS final_24h_count
  FROM
    med_counts
  GROUP BY
    medication_class
),

-- Calculate percentages and differences
final_results AS (
  SELECT
    ac.medication_class,
    ac.first_48h_count,
    ac.final_24h_count,
    (SELECT COUNT(DISTINCT subject_id) FROM patients_with_conditions) AS total_patients,
    ROUND(ac.first_48h_count * 100.0 / (SELECT COUNT(DISTINCT subject_id) FROM patients_with_conditions), 2) AS first_48h_percentage,
    ROUND(ac.final_24h_count * 100.0 / (SELECT COUNT(DISTINCT subject_id) FROM patients_with_conditions), 2) AS final_24h_percentage,
    ROUND((ac.final_24h_count - ac.first_48h_count) * 100.0 / (SELECT COUNT(DISTINCT subject_id) FROM patients_with_conditions), 2) AS absolute_difference_pp
  FROM
    aggregated_counts ac
)

-- Final output
SELECT
  medication_class,
  first_48h_count,
  first_48h_percentage,
  final_24h_count,
  final_24h_percentage,
  absolute_difference_pp
FROM
  final_results
ORDER BY
  medication_class;