WITH dka_patients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.deathtime,
    a.hospital_expire_flag,
    p.anchor_age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 84 AND 94
    AND LOWER(dicd.long_title) LIKE '%diabetic ketoacidosis%'
    AND d.seq_num = 1  -- Use the first (most prominent) DKA diagnosis
),

medications_in_48h AS (
  SELECT
    dp.subject_id,
    dp.hadm_id,
    dp.admittime,
    dp.dischtime,
    dp.hospital_expire_flag,
    COUNT(DISTINCT pr.drug) AS medication_complexity
  FROM dka_patients dp
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON dp.hadm_id = pr.hadm_id
    AND pr.starttime >= dp.admittime
    AND pr.starttime <= dp.admittime + INTERVAL 48 HOUR
  GROUP BY dp.subject_id, dp.hadm_id, dp.admittime, dp.dischtime, dp.hospital_expire_flag
),

hyperkalemia_risk_drugs AS (
  SELECT DISTINCT
    pr.hadm_id,
    CASE
      WHEN LOWER(pr.drug) IN (
        'lisinopril', 'enalapril', 'ramipril', 'captopril', 'benazepril', 'quinapril', 'fosinopril', 'trandolapril',
        'losartan', 'valsartan', 'irbesartan', 'candesartan', 'telmisartan', 'olmesartan', 'eprosartan',
        'spironolactone', 'eplerenone', 'amiloride', 'triamterene',
        'indomethacin', 'ibuprofen', 'naproxen', 'diclofenac', 'ketoprofen', 'meloxicam', 'celecoxib',
        'heparin', 'enoxaparin', 'dalteparin', 'low molecular weight heparin',
        'trimethoprim', 'cotrimoxazole', 'sulfamethoxazole',
        'propranolol', 'atenolol', 'metoprolol', 'carvedilol', 'nadolol', 'labetalol',
        'potassium chloride', 'potassium citrate', 'potassium acetate'
      ) THEN 1
      ELSE 0
    END AS has_hyperkalemia_risk
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
  INNER JOIN dka_patients dp ON pr.hadm_id = dp.hadm_id
  WHERE pr.starttime >= dp.admittime
    AND pr.starttime <= dp.admittime + INTERVAL 48 HOUR
),

hyperkalemia_exposure AS (
  SELECT
    mi.subject_id,
    mi.hadm_id,
    mi.admittime,
    mi.dischtime,
    mi.hospital_expire_flag,
    mi.medication_complexity,
    COALESCE(MAX(hkr.has_hyperkalemia_risk), 0) AS has_hyperkalemia_risk
  FROM medications_in_48h mi
  LEFT JOIN hyperkalemia_risk_drugs hkr ON mi.hadm_id = hkr.hadm_id
  GROUP BY mi.subject_id, mi.hadm_id, mi.admittime, mi.dischtime, mi.hospital_expire_flag, mi.medication_complexity
),

quartiles AS (
  SELECT *,
    NTILE(4) OVER (ORDER BY medication_complexity) AS complexity_quartile
  FROM hyperkalemia_exposure
)

-- Final output: compare groups with vs without hyperkalemia-risk drugs
SELECT
  has_hyperkalemia_risk,
  AVG(medication_complexity) AS mean_medication_complexity,
  PERCENTILE_CONT(medication_complexity, 0.25) OVER () AS p25_complexity,
  PERCENTILE_CONT(medication_complexity, 0.5) OVER () AS median_complexity,
  PERCENTILE_CONT(medication_complexity, 0.75) OVER () AS p75_complexity,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartiles
GROUP BY has_hyperkalemia_risk
ORDER BY has_hyperkalemia_risk

UNION ALL

-- Report LOS and mortality for top quartile (Q4) only
SELECT
  NULL AS has_hyperkalemia_risk,
  NULL AS mean_medication_complexity,
  NULL AS p25_complexity,
  NULL AS median_complexity,
  NULL AS p75_complexity,
  AVG(TIMESTAMP_DIFF(dischtime, admittime, HOUR) / 24.0) AS mean_los_days,
  AVG(hospital_expire_flag) AS mortality_rate
FROM quartiles
WHERE complexity_quartile = 4;