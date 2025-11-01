WITH qualifying_admissions AS (
  SELECT 
    a.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    p.anchor_age,
    TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days,
    CASE 
      WHEN TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) <= 7 THEN '<=7 days'
      ELSE '>7 days'
    END AS los_group,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_icu.icustays` i 
        WHERE i.hadm_id = a.hadm_id 
          AND i.intime >= a.admittime
          AND i.intime <= TIMESTAMP_ADD(a.admittime, INTERVAL 1 DAY)
      ) THEN 'Yes'
      ELSE 'No'
    END AS icu_day1,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = a.hadm_id 
          AND (
            (d.icd_version = 9 AND (d.icd_code LIKE '585%' OR d.icd_code = '586')) OR
            (d.icd_version = 10 AND d.icd_code LIKE 'N18%')
          )
      ) THEN 1 
      ELSE 0 
    END AS has_ckd,
    CASE 
      WHEN EXISTS (
        SELECT 1 
        FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
        WHERE d.hadm_id = a.hadm_id 
          AND (
            (d.icd_version = 9 AND d.icd_code LIKE '250%') OR
            (d.icd_version = 10 AND (d.icd_code LIKE 'E10%' OR d.icd_code LIKE 'E11%' OR 
                                       d.icd_code LIKE 'E12%' OR d.icd_code LIKE 'E13%' OR 
                                       d.icd_code LIKE 'E14%'))
          )
      ) THEN 1 
      ELSE 0 
    END AS has_diabetes
  FROM 
    `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN 
    `physionet-data.mimiciv_3_1_hosp.patients` p ON a.subject_id = p.subject_id
  WHERE 
    p.gender = 'M'
    AND (EXTRACT(YEAR FROM a.admittime) - p.anchor_year + p.anchor_age) BETWEEN 67 AND 77
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d 
      WHERE d.hadm_id = a.hadm_id 
        AND d.seq_num = 1
        AND (
          (d.icd_version = 9 AND d.icd_code LIKE '428%') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'I50%')
        )
    )
)
SELECT 
  los_group,
  icu_day1,
  COUNT(*) AS n_patients,
  ROUND(AVG(CAST(hospital_expire_flag AS FLOAT64)) * 100, 2) AS mortality_pct,
  ROUND(AVG(CAST(has_ckd AS FLOAT64)) * 100, 2) AS ckd_prevalence_pct,
  ROUND(AVG(CAST(has_diabetes AS FLOAT64)) * 100, 2) AS diabetes_prevalence_pct
FROM qualifying_admissions
GROUP BY los_group, icu_day1
ORDER BY 
  CASE WHEN los_group = '<=7 days' THEN 1 ELSE 2 END,
  CASE WHEN icu_day1 = 'No' THEN 1 ELSE 2 END;