WITH patients_of_interest AS (
  SELECT 
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    -- Calculate age at admission
    EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) AS age
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND EXTRACT(YEAR FROM a.admittime) - (p.anchor_year - p.anchor_age) BETWEEN 39 AND 49
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.hadm_id = a.hadm_id
        AND (
          -- Aspiration pneumonia (ICD-9 and ICD-10)
          (d.icd_version = 9 AND d.icd_code = '5070') OR
          (d.icd_version = 10 AND d.icd_code LIKE 'J69%') OR
          -- Community-acquired pneumonia (ICD-9 and ICD-10)
          (d.icd_version = 9 AND d.icd_code BETWEEN '480' AND '486') OR
          (d.icd_version = 10 AND (
            d.icd_code LIKE 'J12%' OR 
            d.icd_code LIKE 'J13%' OR 
            d.icd_code LIKE 'J14%' OR 
            d.icd_code LIKE 'J15%' OR 
            d.icd_code LIKE 'J16%' OR 
            d.icd_code LIKE 'J18%'
          ))
        )
    )
),
admission_data AS (
  SELECT 
    poi.*,
    -- Calculate LOS in fractional days
    DATETIME_DIFF(poi.dischtime, poi.admittime, SECOND) / (24 * 60 * 60) AS los_days,
    -- Determine LOS group
    CASE 
      WHEN DATETIME_DIFF(poi.dischtime, poi.admittime, SECOND) / (24 * 60 * 60) BETWEEN 1 AND 3 THEN '1-3'
      WHEN DATETIME_DIFF(poi.dischtime, poi.admittime, SECOND) / (24 * 60 * 60) BETWEEN 4 AND 7 THEN '4-7'
      WHEN DATETIME_DIFF(poi.dischtime, poi.admittime, SECOND) / (24 * 60 * 60) >= 8 THEN '>=8'
      ELSE 'other'
    END AS los_group,
    -- Check if in ICU on day 1 (first 24 hours)
    CASE WHEN EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_icu.icustays` i
      WHERE i.hadm_id = poi.hadm_id
        AND i.intime >= poi.admittime
        AND i.intime < DATETIME_ADD(poi.admittime, INTERVAL 1 DAY)
    ) THEN 1 ELSE 0 END AS icu_day1
  FROM patients_of_interest poi
  WHERE poi.dischtime IS NOT NULL  -- Ensure valid discharge time
),
comorbidity_counts AS (
  SELECT 
    ad.hadm_id,
    ad.subject_id,
    ad.los_group,
    ad.icu_day1,
    ad.hospital_expire_flag,
    ad.los_days,
    -- Count comorbidities using common Elixhauser conditions (simplified)
    SUM(CASE 
          WHEN d.icd_code IN ('4019','I10') THEN 1  -- Hypertension
          WHEN d.icd_code IN ('25000','E11') THEN 1  -- Diabetes
          WHEN d.icd_code IN ('4280','I509') THEN 1  -- Heart failure
          WHEN d.icd_code IN ('5859','N189') THEN 1  -- Renal failure
          ELSE 0 
        END) AS comorbidity_count
  FROM admission_data ad
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON ad.hadm_id = d.hadm_id
  GROUP BY 1, 2, 3, 4, 5, 6
)
SELECT
  los_group,
  icu_day1,
  COUNT(*) AS patient_count,
  AVG(hospital_expire_flag) AS mortality_rate,
  AVG(comorbidity_count) AS avg_comorbidity_count,
  -- Calculate absolute differences from reference group (1-3 days, non-ICU)
  AVG(hospital_expire_flag) - 
    FIRST_VALUE(AVG(hospital_expire_flag)) OVER (
      PARTITION BY los_group 
      ORDER BY icu_day1
    ) AS abs_diff_from_ref,
  -- Calculate relative differences
  (AVG(hospital_expire_flag) - 
    FIRST_VALUE(AVG(hospital_expire_flag)) OVER (
      PARTITION BY los_group 
      ORDER BY icu_day1
    )) / NULLIF(FIRST_VALUE(AVG(hospital_expire_flag)) OVER (
      PARTITION BY los_group 
      ORDER BY icu_day1
    ), 0) AS rel_diff_from_ref
FROM comorbidity_counts
WHERE los_group != 'other'  -- Only include specified LOS groups
GROUP BY los_group, icu_day1
ORDER BY 
  CASE los_group 
    WHEN '1-3' THEN 1 
    WHEN '4-7' THEN 2 
    WHEN '>=8' THEN 3 
  END,
  icu_day1;