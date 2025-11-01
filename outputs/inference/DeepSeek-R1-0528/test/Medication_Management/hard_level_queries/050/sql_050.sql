WITH aki_admissions AS (
  SELECT DISTINCT
    p.subject_id,
    a.hadm_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag AS mortality,
    DATE_DIFF(a.dischtime, a.admittime, DAY) AS los
  FROM `physionet-data.mimiciv_3_1_hosp.patients` p
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
    ON p.subject_id = a.subject_id
  INNER JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.hadm_id = d.hadm_id
  WHERE 
    p.gender = 'F'
    AND p.anchor_age BETWEEN 81 AND 91
    AND (
      (d.icd_version = 9 AND d.icd_code LIKE '584%') OR
      (d.icd_version = 10 AND d.icd_code LIKE 'N17%')
    )
),

med_class AS (
  SELECT
    hadm_id,
    drug,
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(drug), r'oxycodone|morphine|fentanyl|midazolam|lorazepam|diazepam|alprazolam') 
      THEN 1 ELSE 0 
    END AS is_cns,
    CASE 
      WHEN REGEXP_CONTAINS(LOWER(drug), r'ibuprofen|ketorolac|naproxen|diclofenac|gentamicin|vancomycin|amphotericin') 
      THEN 1 ELSE 0 
    END AS is_nephro
  FROM `physionet-data.mimiciv_3_1_hosp.prescriptions`
),

admission_meds AS (
  SELECT
    hadm_id,
    COUNT(DISTINCT drug) AS complexity,
    MAX(is_cns) AS has_cns,
    MAX(is_nephro) AS has_nephro
  FROM med_class
  GROUP BY hadm_id
),

base AS (
  SELECT
    aki.hadm_id,
    aki.los,
    aki.mortality,
    COALESCE(am.complexity, 0) AS complexity,
    CASE
      WHEN COALESCE(am.has_cns, 0) = 1 AND COALESCE(am.has_nephro, 0) = 1 
      THEN 'both' 
      ELSE 'other' 
    END AS group_flag
  FROM aki_admissions aki
  LEFT JOIN admission_meds am
    ON aki.hadm_id = am.hadm_id
),

group_stats AS (
  SELECT
    group_flag,
    COUNT(*) AS n,
    APPROX_QUANTILES(complexity, 4) AS quartiles,
    AVG(complexity) AS mean_complexity,
    AVG(los) AS mean_los,
    STDDEV(los) AS std_los,
    SUM(mortality) AS mortality_count,
    AVG(mortality) AS mortality_rate
  FROM base
  GROUP BY group_flag
),

group_p75 AS (
  SELECT
    group_flag,
    quartiles[OFFSET(3)] AS p75
  FROM group_stats
),

top_quartile AS (
  SELECT
    base.*
  FROM base
  INNER JOIN group_p75
    ON base.group_flag = group_p75.group_flag
  WHERE base.complexity >= group_p75.p75
),

top_quartile_stats AS (
  SELECT
    group_flag,
    COUNT(*) AS top_quartile_n,
    AVG(los) AS top_quartile_los_mean,
    STDDEV(los) AS top_quartile_los_std,
    SUM(mortality) AS top_quartile_mortality_count,
    AVG(mortality) AS top_quartile_mortality_rate
  FROM top_quartile
  GROUP BY group_flag
)

SELECT
  gs.group_flag,
  gs.n,
  gs.quartiles[OFFSET(1)] AS complexity_25,
  gs.quartiles[OFFSET(2)] AS complexity_50,
  gs.quartiles[OFFSET(3)] AS complexity_75,
  gs.mean_complexity,
  gs.mean_los,
  gs.std_los,
  gs.mortality_count,
  gs.mortality_rate,
  tqs.top_quartile_n,
  tqs.top_quartile_los_mean,
  tqs.top_quartile_los_std,
  tqs.top_quartile_mortality_count,
  tqs.top_quartile_mortality_rate
FROM group_stats gs
LEFT JOIN top_quartile_stats tqs
  ON gs.group_flag = tqs.group_flag
ORDER BY gs.group_flag DESC;  -- 'both' first;