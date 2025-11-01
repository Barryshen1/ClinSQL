WITH dka_codes AS (
  -- List of ICD codes for DKA
  SELECT '25010' AS icd_code, 9 AS icd_version UNION ALL
  SELECT '25011', 9 UNION ALL
  SELECT '25012', 9 UNION ALL
  SELECT '25013', 9 UNION ALL
  SELECT 'E1010', 10 UNION ALL
  SELECT 'E1011', 10 UNION ALL
  SELECT 'E1012', 10 UNION ALL
  SELECT 'E1013', 10 UNION ALL
  SELECT 'E1110', 10 UNION ALL
  SELECT 'E1111', 10 UNION ALL
  SELECT 'E1112', 10 UNION ALL
  SELECT 'E1113', 10 UNION ALL
  SELECT 'E1310', 10 UNION ALL
  SELECT 'E1311', 10 UNION ALL
  SELECT 'E1312', 10 UNION ALL
  SELECT 'E1313', 10 UNION ALL
  SELECT 'E1410', 10 UNION ALL
  SELECT 'E1411', 10 UNION ALL
  SELECT 'E1412', 10 UNION ALL
  SELECT 'E1413', 10
),
hyperk_drugs AS (
  -- List of drug name patterns for hyperkalemia risk
  SELECT 'lisinopril' AS drug UNION ALL
  SELECT 'enalapril' UNION ALL
  SELECT 'ramipril' UNION ALL
  SELECT 'captopril' UNION ALL
  SELECT 'benazepril' UNION ALL
  SELECT 'quinapril' UNION ALL
  SELECT 'perindopril' UNION ALL
  SELECT 'fosinopril' UNION ALL
  SELECT 'moexipril' UNION ALL
  SELECT 'trandolapril' UNION ALL
  SELECT 'losartan' UNION ALL
  SELECT 'valsartan' UNION ALL
  SELECT 'irbesartan' UNION ALL
  SELECT 'candesartan' UNION ALL
  SELECT 'olmesartan' UNION ALL
  SELECT 'telmisartan' UNION ALL
  SELECT 'eprosartan' UNION ALL
  SELECT 'spironolactone' UNION ALL
  SELECT 'eplerenone' UNION ALL
  SELECT 'amiloride' UNION ALL
  SELECT 'triamterene' UNION ALL
  SELECT 'NSAID' UNION ALL
  SELECT 'ibuprofen' UNION ALL
  SELECT 'naproxen' UNION ALL
  SELECT 'indomethacin' UNION ALL
  SELECT 'diclofenac' UNION ALL
  SELECT 'celecoxib' UNION ALL
  SELECT 'meloxicam' UNION ALL
  SELECT 'piroxicam' UNION ALL
  SELECT 'ketorolac' UNION ALL
  SELECT 'heparin' UNION ALL
  SELECT 'trimethoprim' UNION ALL
  SELECT 'sulfamethoxazole'
),
dka_admissions AS (
  -- Get admissions for female patients age 84-94 with DKA
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.deathtime,
    adm.hospital_expire_flag,
    pat.anchor_age,
    pat.gender
  FROM
    physionet-data.mimiciv_3_1_hosp.admissions adm
    JOIN physionet-data.mimiciv_3_1_hosp.patients pat
      ON adm.subject_id = pat.subject_id
    JOIN physionet-data.mimiciv_3_1_hosp.diagnoses_icd diag
      ON adm.hadm_id = diag.hadm_id
    JOIN dka_codes dka
      ON diag.icd_code = dka.icd_code AND diag.icd_version = dka.icd_version
  WHERE
    pat.gender = 'F'
    AND pat.anchor_age BETWEEN 84 AND 94
),
meds_48h AS (
  -- All medications administered/prescribed in first 48h of admission
  SELECT
    p.subject_id,
    p.hadm_id,
    LOWER(p.drug) AS drug,
    p.starttime,
    p.stoptime
  FROM physionet-data.mimiciv_3_1_hosp.prescriptions p
    JOIN dka_admissions adm ON p.hadm_id = adm.hadm_id
  WHERE
    p.starttime >= adm.admittime
    AND p.starttime < TIMESTAMP_ADD(adm.admittime, INTERVAL 48 HOUR)
),
hyperk_exposure AS (
  -- For each admission, count unique hyperkalemia-risk drugs in first 48h
  SELECT
    m.subject_id,
    m.hadm_id,
    COUNT(DISTINCT hk.drug) AS n_hyperk_drugs
  FROM meds_48h m
    JOIN hyperk_drugs hk ON m.drug LIKE CONCAT('%', hk.drug, '%')
  GROUP BY m.subject_id, m.hadm_id
),
complexity AS (
  -- For each admission, count unique drugs in first 48h
  SELECT
    m.subject_id,
    m.hadm_id,
    COUNT(DISTINCT m.drug) AS med_complexity
  FROM meds_48h m
  GROUP BY m.subject_id, m.hadm_id
),
main_cohort AS (
  -- Combine all info for cohort
  SELECT
    adm.subject_id,
    adm.hadm_id,
    adm.admittime,
    adm.dischtime,
    adm.hospital_expire_flag,
    complexity.med_complexity,
    IFNULL(hyperk_exposure.n_hyperk_drugs, 0) AS n_hyperk_drugs,
    CASE WHEN IFNULL(hyperk_exposure.n_hyperk_drugs, 0) >= 2 THEN 'interaction' ELSE 'no_interaction' END AS interaction_status,
    TIMESTAMP_DIFF(adm.dischtime, adm.admittime, HOUR)/24.0 AS los_days
  FROM dka_admissions adm
    LEFT JOIN complexity ON adm.subject_id = complexity.subject_id AND adm.hadm_id = complexity.hadm_id
    LEFT JOIN hyperk_exposure ON adm.subject_id = hyperk_exposure.subject_id AND adm.hadm_id = hyperk_exposure.hadm_id
),
percentiles AS (
  -- Calculate percentile rank for medication complexity
  SELECT
    *,
    PERCENT_RANK() OVER (ORDER BY med_complexity) AS med_complexity_percentile
  FROM main_cohort
),
quartiles AS (
  -- Mark top quartile
  SELECT
    *,
    CASE WHEN med_complexity_percentile >= 0.75 THEN 1 ELSE 0 END AS top_quartile
  FROM percentiles
),
summary AS (
  -- Summary stats by interaction status
  SELECT
    interaction_status,
    COUNT(*) AS n_admissions,
    AVG(med_complexity) AS mean_med_complexity,
    AVG(med_complexity_percentile) AS mean_complexity_percentile,
    AVG(los_days) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM quartiles
  GROUP BY interaction_status
),
top_quartile_summary AS (
  -- LOS and mortality for top quartile by interaction status
  SELECT
    interaction_status,
    COUNT(*) AS n_top_quartile,
    AVG(los_days) AS mean_los_days,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_rate
  FROM quartiles
  WHERE top_quartile = 1
  GROUP BY interaction_status
)
-- Final output
SELECT
  'All admissions' AS group_type,
  s.interaction_status,
  s.n_admissions,
  s.mean_med_complexity,
  s.mean_complexity_percentile,
  s.mean_los_days,
  s.mortality_rate
FROM summary s
UNION ALL
SELECT
  'Top complexity quartile' AS group_type,
  t.interaction_status,
  NULL AS n_admissions,
  NULL AS mean_med_complexity,
  NULL AS mean_complexity_percentile,
  t.mean_los_days,
  t.mortality_rate
FROM top_quartile_summary t
ORDER BY group_type, interaction_status;