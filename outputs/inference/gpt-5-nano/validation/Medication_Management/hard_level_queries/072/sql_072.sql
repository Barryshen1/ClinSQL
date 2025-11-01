WITH dkadmitted AS (
  SELECT DISTINCT
    a.hadm_id,
    a.subject_id,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    p.gender,
    CASE
      WHEN p.anchor_age IS NOT NULL THEN
        p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)
      ELSE NULL
    END AS age_at_adm
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` AS a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` AS p
    ON p.subject_id = a.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
    ON di.hadm_id = a.hadm_id
  WHERE p.gender = 'F'
    AND (
         (di.icd_version = 9 AND di.icd_code LIKE '250.1%')
         OR (di.icd_version = 10 AND (
              di.icd_code LIKE 'E10.1%' OR di.icd_code LIKE 'E11.1%' OR di.icd_code LIKE 'E13.1%'
         ))
        )
),
cohort AS (
  SELECT *
  FROM dkadmitted
  WHERE age_at_adm BETWEEN 84 AND 94
),
meds AS (
  -- compute medication complexity per admission: count distinct drugs started in first 48h
  SELECT
    c.hadm_id,
    c.admittime,
    c.dischtime,
    c.hospital_expire_flag,
    c.age_at_adm,
    COUNT(DISTINCT pr.drug) AS med_complexity,
    MAX(
      CASE
        WHEN LOWER(pr.drug) LIKE '%spironolactone%' OR
             LOWER(pr.drug) LIKE '%triamterene%' OR
             LOWER(pr.drug) LIKE '%amiloride%' OR
             LOWER(pr.drug) LIKE '%eplerenone%' OR
             LOWER(pr.drug) LIKE '%losartan%' OR
             LOWER(pr.drug) LIKE '%lisinopril%' OR
             LOWER(pr.drug) LIKE '%enalapril%' OR
             LOWER(pr.drug) LIKE '%ramipril%' OR
             LOWER(pr.drug) LIKE '%ACE inhibitor%' OR
             LOWER(pr.drug) LIKE '%ARB%' OR
             LOWER(pr.drug) LIKE '%potassium chloride%' OR
             LOWER(pr.drug) LIKE '%heparin%'
        THEN 1
        ELSE 0
      END
    ) AS has_potential_risk
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON pr.subject_id = c.subject_id
   AND pr.hadm_id = c.hadm_id
   AND pr.starttime BETWEEN c.admittime AND TIMESTAMP_ADD(c.admittime, INTERVAL 48 HOUR)
  GROUP BY
    c.hadm_id, c.admittime, c.dischtime, c.hospital_expire_flag, c.age_at_adm
),
quartiled AS (
  -- assign quartiles by medication complexity (ascending order -> top quartile has highest complexity)
  SELECT m.*,
         NTILE(4) OVER (ORDER BY med_complexity ASC) AS quartile4
  FROM meds m
),
agg AS (
  -- Group by risk exposure (Yes/No) to summarize mean complexity and percentiles
  SELECT
    CASE WHEN has_potential_risk = 1 THEN 'Yes' ELSE 'No' END AS risk_group,
    med_complexity
  FROM quartiled
),
topq AS (
  SELECT quartile4, admittime, dischtime, hospital_expire_flag
  FROM quartiled
  WHERE quartile4 = 4
),
los_and_mort AS (
  SELECT
    AVG(TIMESTAMP_DIFF(dischtime, admittime, SECOND) / 3600.0 / 24.0) AS avg_los_topquartile_days,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1.0 ELSE 0.0 END) AS mortality_topquartile_rate
  FROM topq
),
quant AS (
  SELECT risk_group,
         APPROX_QUANTILES(med_complexity, 4) AS q
  FROM agg
  GROUP BY risk_group
)
SELECT
  a.risk_group,
  AVG(a.med_complexity) AS mean_complexity,
  q.q[OFFSET(1)] AS p25_complexity,
  q.q[OFFSET(2)] AS median_complexity,
  q.q[OFFSET(3)] AS p75_complexity,
  NULL AS los_topquartile_days,
  NULL AS mortality_topquartile
FROM agg a
JOIN quant q ON a.risk_group = q.risk_group
GROUP BY a.risk_group, q.q
UNION ALL
SELECT
  'Top quartile' AS risk_group,
  NULL AS mean_complexity,
  NULL AS p25_complexity,
  NULL AS median_complexity,
  NULL AS p75_complexity,
  avg_los_topquartile_days AS los_topquartile_days,
  mortality_topquartile
FROM los_and_mort;