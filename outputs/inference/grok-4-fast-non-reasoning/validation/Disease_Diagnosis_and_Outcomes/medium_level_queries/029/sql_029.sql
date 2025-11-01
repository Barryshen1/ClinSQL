WITH sepsis_codes_without_shock AS (
  SELECT hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE seq_num = 1
    AND icd_version = '10'
    AND REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^(A40|A41)\.')
    AND NOT EXISTS (
      SELECT 1 FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_shock
      WHERE di_shock.hadm_id = diagnoses_icd.hadm_id
        AND di_shock.icd_version = '10'
        AND CAST(di_shock.icd_code AS STRING) = 'R65.21'
    )
),
sepsis_with_shock AS (
  SELECT DISTINCT di.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
  WHERE di.seq_num = 1
    AND di.icd_version = '10'
    AND REGEXP_CONTAINS(CAST(di.icd_code AS STRING), r'^(A40|A41)\.')
    AND EXISTS (
      SELECT 1
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di_shock
      WHERE di_shock.hadm_id = di.hadm_id
        AND di_shock.icd_version = '10'
        AND CAST(di_shock.icd_code AS STRING) = 'R65.21'
    )
),
all_diagnoses AS (
  SELECT hadm_id, icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
),
charlson_weights AS (
  SELECT 
    hadm_id,
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^I21|I22|I25\.2') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^I09\.8|I09\.9|I11\.0|I13\.0|I13\.2|I42\.0|I42\.5-I42\.9|I43|I50|P29\.0') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^I70\.0-I70\.92|K55\.1|K55\.8|I73\.1|I73\.8|I73\.9|I77\.1|I79\.0|I97\.1|K95\.81|Z95\.810') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^F00-F03|G30') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^I27\.8|I27\.9|J40-J47|J60-J67|J68\.4|J70\.0|J70\.1|J70\.3') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^M05|M06|M08|M12\.0|M12\.3|M31\.2|M31\.3|M32-M35|G73\.7|K68\.8') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^K25-K27') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^B18\.0|B18\.1|K60\.3|K60\.4|K60\.8|K60\.9|K73|K74|K76\.6|I85|I86\.4|I98\.2') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^E10-E14') AND NOT REGEXP_CONTAINS(CAST(icd_code AS STRING), r'\.2$|\.3$|\.4$') THEN 1 ELSE 0 END) > 0 THEN 1 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^G81|G82|G83\.0-G83\.4|G83\.9|G86|R53\.8') THEN 1 ELSE 0 END) > 0 THEN 2 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^I12\.0|I13\.1|N18|N19|N25\.4|Z49\.2|Z99\.2') THEN 1 ELSE 0 END) > 0 THEN 2 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^E10\.2-E10\.8|E11\.2-E11\.8|E12\.2-E12\.8|E13\.2-E13\.8|E14\.2-E14\.8') THEN 1 ELSE 0 END) > 0 THEN 2 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^C00-C97') AND NOT REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^C81-C96') THEN 1 ELSE 0 END) > 0 THEN 2 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^I85\.0|I85\.1|I85\.3|I98\.0|K70\.0-K70\.4|K70\.9|K71\.1|K73|K74|K76\.6|I98\.2') THEN 1 ELSE 0 END) > 0 THEN 2 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^C77-C80') THEN 1 ELSE 0 END) > 0 THEN 3 ELSE 0 END) +
    (CASE WHEN SUM(CASE WHEN REGEXP_CONTAINS(CAST(icd_code AS STRING), r'^B20-B24') THEN 1 ELSE 0 END) > 0 THEN 6 ELSE 0 END) AS cci_score
  FROM all_diagnoses
  WHERE icd_version = '10'
  GROUP BY hadm_id
),
cohort AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    COALESCE(cw.cci_score, 0) AS cci_score,
    CASE 
      WHEN ssw.hadm_id IS NOT NULL THEN 'septic_shock'
      WHEN sws.hadm_id IS NOT NULL THEN 'sepsis_without_shock'
      ELSE NULL
    END AS sepsis_group,
    DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) AS los_days,
    CASE WHEN DATE_DIFF(DATE(a.dischtime), DATE(a.admittime), DAY) <= 7 THEN '<=7' ELSE '>7' END AS los_group,
    CASE 
      WHEN COALESCE(cw.cci_score, 0) <= 3 THEN '<=3'
      WHEN COALESCE(cw.cci_score, 0) BETWEEN 4 AND 5 THEN '4-5'
      ELSE '>5'
    END AS charlson_group
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  LEFT JOIN sepsis_codes_without_shock sws ON a.hadm_id = sws.hadm_id
  LEFT JOIN sepsis_with_shock ssw ON a.hadm_id = ssw.hadm_id
  LEFT JOIN charlson_weights cw ON a.hadm_id = cw.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 57 AND 67
    AND (sws.hadm_id IS NOT NULL OR ssw.hadm_id IS NOT NULL)
),
aggregated_mortality AS (
  SELECT 
    sepsis_group,
    los_group,
    charlson_group,
    COUNT(*) AS total_patients,
    SUM(CAST(hospital_expire_flag AS INT64)) AS deceased,
    SAFE_DIVIDE(SUM(CAST(hospital_expire_flag AS INT64)) * 100.0, COUNT(*)) AS mortality_pct
  FROM cohort
  WHERE sepsis_group IS NOT NULL
  GROUP BY sepsis_group, los_group, charlson_group
),
differences AS (
  SELECT 
    los_group,
    charlson_group,
    MAX(CASE WHEN sepsis_group = 'septic_shock' THEN mortality_pct END) AS shock_mort,
    MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN mortality_pct END) AS without_mort,
    MAX(CASE WHEN sepsis_group = 'septic_shock' THEN total_patients END) AS shock_n,
    MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN total_patients END) AS without_n,
    (MAX(CASE WHEN sepsis_group = 'septic_shock' THEN mortality_pct END) - 
     MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN mortality_pct END)) AS abs_diff_pct,
    SAFE_DIVIDE(
      (MAX(CASE WHEN sepsis_group = 'septic_shock' THEN mortality_pct END) - 
       MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN mortality_pct END)), 
      MAX(CASE WHEN sepsis_group = 'sepsis_without_shock' THEN mortality_pct END)
    ) * 100 AS rel_diff_pct
  FROM aggregated_mortality
  GROUP BY los_group, charlson_group
)
SELECT 
  los_group,
  charlson_group,
  without_n AS without_shock_n,
  shock_n AS shock_n,
  ROUND(without_mort, 2) AS without_shock_mortality_pct,
  ROUND(shock_mort, 2) AS shock_mortality_pct,
  ROUND(abs_diff_pct, 2) AS absolute_difference_pct,
  ROUND(rel_diff_pct, 2) AS relative_difference_pct
FROM differences
ORDER BY los_group, charlson_group;