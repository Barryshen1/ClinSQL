WITH classes AS (
  SELECT 'Antidiabetic' AS drug_class UNION ALL
  SELECT 'Beta-Blocker' UNION ALL
  SELECT 'ACEi/ARB/ARNI' UNION ALL
  SELECT 'Loop Diuretic'
),
cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, a.admittime, a.dischtime
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a ON p.subject_id = a.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 49 AND 59
    AND a.admission_type != 'OBSERVATION'
),
has_t2dm AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'E11%')
     OR (icd_version = 9 AND icd_code LIKE '250.%')
),
has_hf AS (
  SELECT DISTINCT subject_id, hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE (icd_version = 10 AND icd_code LIKE 'I50%')
     OR (icd_version = 9 AND icd_code LIKE '428%')
),
patient_cohort AS (
  SELECT c.*
  FROM cohort c
  INNER JOIN has_t2dm t ON c.subject_id = t.subject_id AND c.hadm_id = t.hadm_id
  INNER JOIN has_hf h ON c.subject_id = h.subject_id AND c.hadm_id = h.hadm_id
),
med_presc AS (
  -- Antidiabetic (partial list; expand as needed)
  SELECT subject_id, hadm_id, starttime, stoptime, 'Antidiabetic' AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN ('Metformin', 'Metformin HCl', 'Glipizide', 'Glimepiride', 'Glyburide', 'Pioglitazone', 'Sitagliptin', 'Linagliptin', 'Dulaglutide', 'Semaglutide')
     OR drug LIKE '%Insulin%'
  UNION ALL
  -- Beta-Blocker (partial list)
  SELECT subject_id, hadm_id, starttime, stoptime, 'Beta-Blocker' AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN ('Metoprolol Tartrate', 'Metoprolol Succinate', 'Metoprolol', 'Carvedilol', 'Bisoprolol', 'Atenolol', 'Propranolol', 'Labetalol')
  UNION ALL
  -- ACEi/ARB/ARNI (partial list)
  SELECT subject_id, hadm_id, starttime, stoptime, 'ACEi/ARB/ARNI' AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN ('Lisinopril', 'Enalapril', 'Ramipril', 'Benazepril', 'Losartan', 'Valsartan', 'Irbesartan', 'Candesartan', 'Sacubitril/Valsartan', 'Entresto')
  UNION ALL
  -- Loop Diuretic (partial list)
  SELECT subject_id, hadm_id, starttime, stoptime, 'Loop Diuretic' AS drug_class
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IN ('Furosemide', 'Lasix', 'Bumetanide', 'Torsemide')
),
patient_class AS (
  SELECT pc.subject_id, pc.hadm_id, pc.admittime, pc.dischtime, cl.drug_class
  FROM patient_cohort pc
  CROSS JOIN classes cl
),
status AS (
  SELECT
    pc.subject_id,
    pc.hadm_id,
    pc.drug_class,
    MAX(CASE
      WHEN m.starttime <= pc.admittime + INTERVAL 1 DAY
        AND (m.stoptime IS NULL OR m.stoptime >= pc.admittime)
        AND m.drug_class = pc.drug_class
      THEN 1 ELSE 0
    END) AS on_first,
    MAX(CASE
      WHEN m.starttime <= pc.dischtime
        AND (m.stoptime IS NULL OR m.stoptime >= GREATEST(pc.dischtime - INTERVAL 2 DAY, pc.admittime))
        AND m.drug_class = pc.drug_class
      THEN 1 ELSE 0
    END) AS on_final
  FROM patient_class pc
  LEFT JOIN med_presc m
    ON pc.subject_id = m.subject_id
    AND pc.hadm_id = m.hadm_id
    AND pc.drug_class = m.drug_class
  GROUP BY pc.subject_id, pc.hadm_id, pc.drug_class
)
SELECT
  drug_class,
  COUNT(*) AS total_patients,
  COUNTIF(on_first = 1) AS on_first_count,
  ROUND(COUNTIF(on_first = 1) * 100.0 / COUNT(*), 2) AS percent_first,
  COUNTIF(on_final = 1) AS on_final_count,
  ROUND(COUNTIF(on_final = 1) * 100.0 / COUNT(*), 2) AS percent_final,
  COUNTIF(on_first = 1 AND on_final = 1) AS continued,
  COUNTIF(on_first = 0 AND on_final = 1) AS initiated,
  COUNTIF(on_first = 1 AND on_final = 0) AS discontinued,
  COUNTIF(on_first = 0 AND on_final = 0) AS none
FROM status
GROUP BY drug_class
ORDER BY drug_class;