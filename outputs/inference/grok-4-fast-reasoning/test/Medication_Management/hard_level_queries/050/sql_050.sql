WITH cohort AS (
  SELECT 
    p.subject_id, 
    a.hadm_id, 
    a.admittime, 
    a.dischtime, 
    a.hospital_expire_flag,
    p.anchor_age,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a 
    ON p.subject_id = a.subject_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND EXISTS (
      SELECT 1 
      FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      WHERE d.subject_id = p.subject_id 
        AND d.hadm_id = a.hadm_id
        AND (
          (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
          OR (d.icd_version = 9 AND d.icd_code LIKE '584%')
        )
    )
),
meds AS (
  SELECT 
    hadm_id, 
    LOWER(TRIM(drug)) AS drug_lower
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
  WHERE drug IS NOT NULL
),
has_cns AS (
  SELECT DISTINCT hadm_id
  FROM meds
  WHERE drug_lower LIKE '%morphine%'
     OR drug_lower LIKE '%fentanyl%'
     OR drug_lower LIKE '%hydromorphone%'
     OR drug_lower LIKE '%oxycodone%'
     OR drug_lower LIKE '%hydrocodone%'
     OR drug_lower LIKE '%lorazepam%'
     OR drug_lower LIKE '%diazepam%'
     OR drug_lower LIKE '%midazolam%'
),
has_nephro AS (
  SELECT DISTINCT hadm_id
  FROM meds
  WHERE drug_lower LIKE '%gentamicin%'
     OR drug_lower LIKE '%tobramycin%'
     OR drug_lower LIKE '%vancomycin%'
     OR drug_lower LIKE '%amphotericin%'
     OR drug_lower LIKE '%ibuprofen%'
     OR drug_lower LIKE '%ketorolac%'
     OR drug_lower LIKE '%indomethacin%'
),
complexity AS (
  SELECT 
    c.hadm_id, 
    c.los, 
    c.hospital_expire_flag,
    COUNT(DISTINCT COALESCE(m.drug_lower, '')) AS complexity_score,  -- 0 if no meds
    CASE 
      WHEN hcn.hadm_id IS NOT NULL AND hne.hadm_id IS NOT NULL THEN 'Both'
      ELSE 'Other'
    END AS group_type
  FROM cohort c
  LEFT JOIN meds m 
    ON c.hadm_id = m.hadm_id
  LEFT JOIN has_cns hcn 
    ON c.hadm_id = hcn.hadm_id
  LEFT JOIN has_nephro hne 
    ON c.hadm_id = hne.hadm_id
  GROUP BY 
    c.hadm_id, c.los, c.hospital_expire_flag, hcn.hadm_id, hne.hadm_id
),
base_stats AS (
  SELECT 
    group_type,
    AVG(complexity_score) AS mean_complexity,
    APPROX_QUANTILES(complexity_score, 4)[OFFSET(0)] AS q1_complexity,
    APPROX_QUANTILES(complexity_score, 4)[OFFSET(1)] AS q2_complexity,
    APPROX_QUANTILES(complexity_score, 4)[OFFSET(2)] AS q3_complexity,
    AVG(los) AS mean_los_overall,
    AVG(CAST(hospital_expire_flag AS FLOAT64)) AS mortality_overall
  FROM complexity
  GROUP BY group_type
),
q3_per_group AS (
  SELECT 
    group_type,
    APPROX_QUANTILES(complexity_score, 4)[OFFSET(2)] AS q3_complexity
  FROM complexity
  GROUP BY group_type
),
topq_stats AS (
  SELECT 
    c.group_type,
    AVG(c.los) AS mean_los_topq,
    AVG(CAST(c.hospital_expire_flag AS FLOAT64)) AS mortality_topq
  FROM complexity c
  JOIN q3_per_group q 
    ON c.group_type = q.group_type
  WHERE c.complexity_score >= q.q3_complexity
  GROUP BY c.group_type
)
SELECT 
  b.group_type,
  b.mean_complexity,
  b.q1_complexity,
  b.q2_complexity,
  b.q3_complexity,
  b.mean_los_overall,
  b.mortality_overall,
  t.mean_los_topq,
  t.mortality_topq
FROM base_stats b
JOIN topq_stats t 
  ON b.group_type = t.group_type
ORDER BY 
  CASE WHEN b.group_type = 'Both' THEN 1 ELSE 2 END;