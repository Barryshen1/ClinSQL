WITH aki_cohort AS (
  -- Base cohort: females 81-91 with AKI (top 5 diagnoses)
  SELECT DISTINCT 
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
    ON a.hadm_id = d.hadm_id AND d.seq_num <= 5
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` icd 
    ON d.icd_code = icd.icd_code 
    AND (d.icd_version = icd.icd_version OR (d.icd_version IS NULL AND icd.icd_version IS NULL))
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (icd.icd_code LIKE 'N17.%' OR icd.icd_code LIKE '584.%')  -- AKI ICD-10/9
    AND (a.admission_location IN ('FLOOR', 'ICU') OR (a.admission_location = 'EMERGENCY' AND a.edregtime IS NULL))  -- Inpatients
    AND (a.deathtime IS NULL OR TIMESTAMP_DIFF(a.deathtime, a.admittime, HOUR) > 24)  -- Exclude immediate deaths
    AND a.hadm_id IS NOT NULL
),
med_exposures AS (
  -- Drug exposure from prescriptions only (hospital-wide)
  SELECT 
    ac.subject_id,
    ac.hadm_id,
    pres.drug AS drug_name,
    pres.starttime
  FROM aki_cohort ac
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pres 
    ON ac.hadm_id = pres.hadm_id
    AND pres.starttime >= ac.admittime 
    AND (pres.stoptime <= ac.dischtime OR pres.stoptime IS NULL)
  WHERE pres.drug IS NOT NULL
    AND pres.drug_type = 'MAIN'  -- Focus on main orders
),
drug_flags AS (
  -- Flag exposure to nephrotoxic and CNS-depressant drugs, plus unique drug count
  SELECT 
    hadm_id,
    MAX(CASE WHEN REGEXP_CONTAINS(UPPER(drug_name), r'(VANCOMYCIN|GENTAMICIN|IBUPROFEN|NAPROXEN|INDOMETHACIN|LISINOPRIL|ENALAPRIL|RAMIPRIL|FURSEMIDE|ACYCLOVIR|AMPHOTERICIN|COLISTIN|NSAID)') 
             THEN 1 ELSE 0 END) AS has_nephrotoxic,
    MAX(CASE WHEN REGEXP_CONTAINS(UPPER(drug_name), r'(MORPHINE|FENTANYL|HYDROMORPHONE|LOPERAZEPAM|MIDAZOLAM|PROPOFOL|ZOLPIDEM|DEXMEDETOMIDINE|HALOPERIDOL)') 
             THEN 1 ELSE 0 END) AS has_cns_depressant,
    COUNT(DISTINCT drug_name) AS unique_drugs
  FROM med_exposures
  GROUP BY hadm_id
),
mcs_calc AS (
  -- Simplified MCS: unique drugs (no redundant flag addition)
  SELECT 
    ac.*,
    COALESCE(df.has_nephrotoxic, 0) AS nephro_flag,
    COALESCE(df.has_cns_depressant, 0) AS cns_flag,
    COALESCE(df.unique_drugs, 0) AS mcs_score
  FROM aki_cohort ac
  LEFT JOIN drug_flags df ON ac.hadm_id = df.hadm_id
),
los_q3 AS (
  -- Compute global LOS Q3 for top-quartile reference
  SELECT APPROX_QUANTILES(los_days, 4)[OFFSET(3)] AS global_los_q3
  FROM mcs_calc
),
grouped_stats AS (
  SELECT 
    CASE 
      WHEN nephro_flag = 1 AND cns_flag = 1 THEN 'Both CNS-depressant and Nephrotoxic'
      ELSE 'Other AKI'
    END AS exposure_group,
    -- MCS distribution
    APPROX_QUANTILES(mcs_score, 4)[OFFSET(1)] AS mcs_q1,
    APPROX_QUANTILES(mcs_score, 4)[OFFSET(2)] AS mcs_median,
    APPROX_QUANTILES(mcs_score, 4)[OFFSET(3)] AS mcs_q3,
    AVG(mcs_score) AS mcs_mean,
    COUNT(*) AS n_patients,
    -- Overall outcomes
    AVG(los_days) AS avg_los,
    SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)), COUNT(*)) AS mortality_rate,
    -- Top-quartile LOS (LOS > global Q3)
    AVG(CASE WHEN los_days > lq.global_los_q3 THEN los_days END) AS top_q_los_avg,
    COUNT(CASE WHEN los_days > lq.global_los_q3 THEN 1 END) AS top_q_n,
    SAFE_DIVIDE(
      SUM(CASE WHEN los_days > lq.global_los_q3 THEN CAST(hospital_expire_flag AS INT64) ELSE 0 END),
      COUNT(CASE WHEN los_days > lq.global_los_q3 THEN 1 END)
    ) AS top_q_mortality_rate
  FROM mcs_calc
  CROSS JOIN los_q3 lq
  GROUP BY exposure_group, lq.global_los_q3
)
SELECT 
  exposure_group,
  mcs_q1, mcs_median, mcs_q3, mcs_mean,
  n_patients,
  avg_los, mortality_rate,
  top_q_los_avg, top_q_n, top_q_mortality_rate
FROM grouped_stats
ORDER BY exposure_group;