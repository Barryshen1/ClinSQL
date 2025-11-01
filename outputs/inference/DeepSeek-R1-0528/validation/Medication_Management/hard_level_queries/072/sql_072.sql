WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  WHERE 
    p.gender = 'F'
    AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 84 AND 94
    AND a.hadm_id IN (
      SELECT hadm_id
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE 
        (d.icd_version = 9 AND d.icd_code IN ('25010','25011','25012','25013','25020','25021','25022','25023','25030','25031','25032','25033'))
        OR 
        (d.icd_version = 10 AND REGEXP_CONTAINS(d.icd_code, r'^(E101|E111|E131|E141|E151)'))
    )
),
drug_data AS (
  SELECT 
    c.hadm_id,
    MAX(
      CASE WHEN 
        LOWER(pr.drug) LIKE '%potassium%' OR
        LOWER(pr.drug) LIKE '%spironolactone%' OR
        LOWER(pr.drug) LIKE '%eplerenone%' OR
        LOWER(pr.drug) LIKE '%triamterene%' OR
        LOWER(pr.drug) LIKE '%amiloride%' OR
        LOWER(pr.drug) LIKE '%lisinopril%' OR
        LOWER(pr.drug) LIKE '%enalapril%' OR
        LOWER(pr.drug) LIKE '%ramipril%' OR
        LOWER(pr.drug) LIKE '%captopril%' OR
        LOWER(pr.drug) LIKE '%benazepril%' OR
        LOWER(pr.drug) LIKE '%perindopril%' OR
        LOWER(pr.drug) LIKE '%quinapril%' OR
        LOWER(pr.drug) LIKE '%trandolapril%' OR
        LOWER(pr.drug) LIKE '%losartan%' OR
        LOWER(pr.drug) LIKE '%valsartan%' OR
        LOWER(pr.drug) LIKE '%irbesartan%' OR
        LOWER(pr.drug) LIKE '%candesartan%' OR
        LOWER(pr.drug) LIKE '%telmisartan%' OR
        LOWER(pr.drug) LIKE '%olmesartan%' OR
        LOWER(pr.drug) LIKE '%azilsartan%' OR
        LOWER(pr.drug) LIKE '%nsaid%' OR
        LOWER(pr.drug) LIKE '%nonsteroidal anti-inflammatory%' OR
        LOWER(pr.drug) LIKE '%ibuprofen%' OR
        LOWER(pr.drug) LIKE '%naproxen%' OR
        LOWER(pr.drug) LIKE '%diclofenac%' OR
        LOWER(pr.drug) LIKE '%celecoxib%' OR
        LOWER(pr.drug) LIKE '%meloxicam%' OR
        LOWER(pr.drug) LIKE '%indomethacin%' OR
        LOWER(pr.drug) LIKE '%heparin%' OR
        LOWER(pr.drug) LIKE '%trimethoprim%' 
      THEN 1 ELSE 0 END
    ) AS hyperkalemia_risk_drug_flag,
    COUNT(DISTINCT pr.drug) AS complexity
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime <= TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
    AND (pr.stoptime IS NULL OR pr.stoptime > c.admittime)
  GROUP BY c.hadm_id
),
combined AS (
  SELECT 
    c.*,
    COALESCE(d.hyperkalemia_risk_drug_flag, 0) AS hyperkalemia_risk_drug_flag,
    COALESCE(d.complexity, 0) AS complexity,
    TIMESTAMP_DIFF(c.dischtime, c.admittime, HOUR) / 24.0 AS los_days
  FROM cohort c
  LEFT JOIN drug_data d
    ON c.hadm_id = d.hadm_id
),
quartiles AS (
  SELECT APPROX_QUANTILES(complexity, 4) AS q_arr FROM combined
)

SELECT 
  'Group Comparison' AS part,
  CASE 
    WHEN hyperkalemia_risk_drug_flag = 1 THEN 'Exposed' 
    ELSE 'Not Exposed' 
  END AS exposure_group,
  COUNT(*) AS n_patients,
  AVG(complexity) AS mean_complexity,
  APPROX_QUANTILES(complexity, 100)[OFFSET(25)] AS p25_complexity,
  APPROX_QUANTILES(complexity, 100)[OFFSET(50)] AS p50_complexity,
  APPROX_QUANTILES(complexity, 100)[OFFSET(75)] AS p75_complexity,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM combined
GROUP BY exposure_group

UNION ALL

SELECT 
  'Top Quartile' AS part,
  NULL AS exposure_group,
  COUNT(*) AS n_patients,
  NULL AS mean_complexity,
  NULL AS p25_complexity,
  NULL AS p50_complexity,
  NULL AS p75_complexity,
  AVG(los_days) AS mean_los,
  APPROX_QUANTILES(los_days, 100)[OFFSET(50)] AS median_los,
  AVG(hospital_expire_flag) AS mortality_rate
FROM combined
WHERE complexity >= (SELECT q_arr[OFFSET(3)] FROM quartiles);