WITH acs_icd_codes AS (
  -- ICD-9: 410-414; ICD-10: I20-I25
  SELECT icd_code, icd_version
  FROM `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses`
  WHERE 
    (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^41[0-4]'))
    OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^I2[0-5]'))
),
acs_admissions AS (
  SELECT DISTINCT d.subject_id, d.hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  INNER JOIN acs_icd_codes icd
    ON d.icd_code = icd.icd_code AND d.icd_version = icd.icd_version
),
male_elderly_acs AS (
  SELECT a.subject_id, a.hadm_id, p.anchor_age
  FROM acs_admissions a
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  WHERE p.gender = 'M'
    AND p.anchor_age BETWEEN 87 AND 97
),
troponin_t_items AS (
  SELECT itemid
  FROM `physionet-data.mimiciv_3_1_hosp.d_labitems`
  WHERE LOWER(label) LIKE '%troponin t%'
),
index_troponin AS (
  -- Get earliest Troponin T per admission
  SELECT
    l.subject_id,
    l.hadm_id,
    l.valuenum,
    l.valueuom,
    l.charttime,
    ROW_NUMBER() OVER (PARTITION BY l.subject_id, l.hadm_id ORDER BY l.charttime ASC) AS rn
  FROM `physionet-data.mimiciv_3_1_hosp.labevents` l
  INNER JOIN troponin_t_items tti
    ON l.itemid = tti.itemid
  WHERE l.valuenum IS NOT NULL
    AND (l.valueuom = 'ng/mL' OR l.valueuom IS NULL)
),
cohort_with_troponin AS (
  SELECT
    m.subject_id,
    m.hadm_id,
    m.anchor_age,
    i.valuenum AS troponin_t,
    i.charttime
  FROM male_elderly_acs m
  INNER JOIN index_troponin i
    ON m.subject_id = i.subject_id AND m.hadm_id = i.hadm_id
  WHERE i.rn = 1
),
cohort_with_mortality AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    c.anchor_age,
    c.troponin_t,
    a.hospital_expire_flag
  FROM cohort_with_troponin c
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON c.subject_id = a.subject_id AND c.hadm_id = a.hadm_id
),
categorized AS (
  SELECT
    *,
    CASE
      WHEN troponin_t < 0.01 THEN 'Normal/Minimal'
      WHEN troponin_t >= 0.01 AND troponin_t < 0.03 THEN 'Borderline'
      WHEN troponin_t >= 0.03 THEN 'Elevated'
      ELSE 'Unknown'
    END AS troponin_t_category
  FROM cohort_with_mortality
)
SELECT
  troponin_t_category,
  COUNT(*) AS n_admissions,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percent_of_total,
  SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) AS n_deaths,
  ROUND(SUM(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS mortality_rate
FROM categorized
WHERE troponin_t_category IN ('Normal/Minimal', 'Borderline', 'Elevated')
GROUP BY troponin_t_category
ORDER BY
  CASE troponin_t_category
    WHEN 'Normal/Minimal' THEN 1
    WHEN 'Borderline' THEN 2
    WHEN 'Elevated' THEN 3
    ELSE 4
  END;