WITH akipatients AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag
  FROM physionet-data.mimiciv_3_1_hosp.patients p
  INNER JOIN physionet-data.mimiciv_3_1_hosp.admissions a
    ON p.subject_id = a.subject_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd d
    ON a.hadm_id = d.hadm_id
  INNER JOIN physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses dicd
    ON d.icd_code = dicd.icd_code AND d.icd_version = dicd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      LOWER(dicd.long_title) LIKE '%acute kidney injury%'
      OR LOWER(dicd.long_title) LIKE '%acute renal failure%'
      OR d.icd_code IN ('N17.0', 'N17.1', 'N17.2', 'N17.8', 'N17.9', 'N17')
    )
),

cns_drugs AS (
  SELECT DISTINCT LOWER(drug) AS drug
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE LOWER(drug) IN (
    'morphine', 'fentanyl', 'hydromorphone', 'oxycodone', 'codeine', 'methadone',
    'lorazepam', 'midazolam', 'diazepam', 'alprazolam', 'clonazepam',
    'phenobarbital', 'pentobarbital',
    'haloperidol', 'risperidone', 'olanzapine', 'quetiapine',
    'zolpidem', 'eszopiclone', 'zaleplon',
    'propofol', 'dexmedetomidine', 'ketamine'
  )
  OR LOWER(drug) LIKE '%opiate%' OR LOWER(drug) LIKE '%opioid%'
  OR LOWER(drug) LIKE '%benzo%' OR LOWER(drug) LIKE '%sedative%'
),

nephrotoxins AS (
  SELECT DISTINCT LOWER(drug) AS drug
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions
  WHERE LOWER(drug) IN (
    'gentamicin', 'tobramycin', 'amikacin', 'neomycin',
    'vancomycin',
    'ibuprofen', 'naproxen', 'indomethacin', 'diclofenac', 'celecoxib',
    'iodinated contrast', 'contrast', 'iohexol', 'ioversol',
    'amphotericin b', 'cisplatin', 'carboplatin', 'ifosfamide',
    'cyclosporine', 'tacrolimus', 'sirolimus'
  )
  OR LOWER(drug) LIKE '%aminoglycoside%' OR LOWER(drug) LIKE '%nsaid%'
  OR LOWER(drug) LIKE '%contrast%' OR LOWER(drug) LIKE '%radiocontrast%'
),

medication_exposure AS (
  SELECT
    a.hadm_id,
    COUNT(DISTINCT p.drug) AS medication_complexity_score,
    MAX(CASE WHEN cd.drug IS NOT NULL THEN 1 ELSE 0 END) AS has_cns_depressant,
    MAX(CASE WHEN nt.drug IS NOT NULL THEN 1 ELSE 0 END) AS has_nephrotoxin,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    a.hospital_expire_flag
  FROM akipatients a
  LEFT JOIN physionet-data.mimiciv_3_1_hosp.prescriptions p
    ON a.hadm_id = p.hadm_id AND p.drug IS NOT NULL
  LEFT JOIN cns_drugs cd ON LOWER(p.drug) = cd.drug
  LEFT JOIN nephrotoxins nt ON LOWER(p.drug) = nt.drug
  GROUP BY a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
),

exposure_groups AS (
  SELECT *,
    CASE 
      WHEN has_cns_depressant = 1 AND has_nephrotoxin = 1 THEN 'Both CNS and Nephrotoxic'
      ELSE 'Other'
    END AS exposure_group
  FROM medication_exposure
),

quartiles AS (
  SELECT
    exposure_group,
    medication_complexity_score,
    los_days,
    hospital_expire_flag,
    NTILE(4) OVER (ORDER BY los_days) AS los_quartile,
    PERCENTILE_CONT(medication_complexity_score, 0.25) OVER () AS q1_complexity,
    PERCENTILE_CONT(medication_complexity_score, 0.50) OVER () AS q2_complexity,
    PERCENTILE_CONT(medication_complexity_score, 0.75) OVER () AS q3_complexity,
    AVG(medication_complexity_score) OVER () AS mean_complexity,
    AVG(los_days) OVER () AS mean_los,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) OVER () AS mortality_rate
  FROM exposure_groups
)

SELECT
  exposure_group,
  AVG(medication_complexity_score) AS mean_medication_complexity,
  PERCENTILE_CONT(medication_complexity_score, 0.25) AS q1_complexity,
  PERCENTILE_CONT(medication_complexity_score, 0.50) AS q2_complexity,
  PERCENTILE_CONT(medication_complexity_score, 0.75) AS q3_complexity,
  AVG(los_days) AS mean_los,
  AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate,
  AVG(CASE WHEN los_quartile = 4 THEN los_days END) AS top_quartile_los,
  AVG(CASE WHEN los_quartile = 4 THEN CAST(hospital_expire_flag AS FLOAT64) END) AS top_quartile_mortality
FROM quartiles
GROUP BY exposure_group
ORDER BY exposure_group;