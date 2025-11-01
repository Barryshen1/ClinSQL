WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
    a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(dd.long_title) LIKE '%trauma%'
    AND (LOWER(dd.long_title) LIKE '%multiple trauma%'
         OR LOWER(dd.long_title) LIKE '%polytrauma%'
         OR LOWER(dd.long_title) LIKE '%multitrauma%')
),
meds24h AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(DISTINCT LOWER(pr.drug)) AS complexity,
         MAX( CASE WHEN LOWER(pr.drug) LIKE '%sertraline%'
                      OR LOWER(pr.drug) LIKE '%fluoxetine%'
                      OR LOWER(pr.drug) LIKE '%paroxetine%'
                      OR LOWER(pr.drug) LIKE '%citalopram%'
                      OR LOWER(pr.drug) LIKE '%escitalopram%'
                      OR LOWER(pr.drug) LIKE '%venlafaxine%'
                      OR LOWER(pr.drug) LIKE '%duloxetine%'
                      OR LOWER(pr.drug) LIKE '%trazodone%'
                      OR LOWER(pr.drug) LIKE '%triptan%'
                      OR LOWER(pr.drug) LIKE '%linezolid%'
                    THEN 1 ELSE 0 END ) AS serotonergic_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
complexity_stats AS (
  SELECT m.*,
         c.admittime, c.dischtime, c.hospital_expire_flag,
         NTILE(4) OVER (ORDER BY complexity) AS complexity_quartile,
         PERCENT_RANK() OVER (ORDER BY complexity) AS complexity_percentile,
         DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM meds24h m
  JOIN cohort c
    ON m.subject_id = c.subject_id AND m.hadm_id = c.hadm_id
)
SELECT serotonergic_flag,
       AVG(complexity_percentile) AS avg_complexity_percentile,
       COUNTIF(complexity_quartile = 1) AS q1_count,
       COUNTIF(complexity_quartile = 2) AS q2_count,
       COUNTIF(complexity_quartile = 3) AS q3_count,
       COUNTIF(complexity_quartile = 4) AS q4_count,
       AVG(los_days) AS avg_los_days,
       AVG(hospital_expire_flag) AS mortality_rate
FROM complexity_stats
GROUP BY serotonergic_flag
ORDER BY serotonergic_flag;

-- Part 2: Top quartile only - redefine CTEs so it's self‑contained
WITH cohort AS (
  SELECT DISTINCT a.subject_id, a.hadm_id, p.gender, p.anchor_age,
    a.admittime, a.dischtime, a.hospital_expire_flag
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
    ON a.subject_id = d.subject_id AND a.hadm_id = d.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
    ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 68 AND 78
    AND LOWER(dd.long_title) LIKE '%trauma%'
    AND (LOWER(dd.long_title) LIKE '%multiple trauma%'
         OR LOWER(dd.long_title) LIKE '%polytrauma%'
         OR LOWER(dd.long_title) LIKE '%multitrauma%')
),
meds24h AS (
  SELECT c.subject_id, c.hadm_id,
         COUNT(DISTINCT LOWER(pr.drug)) AS complexity,
         MAX( CASE WHEN LOWER(pr.drug) LIKE '%sertraline%'
                      OR LOWER(pr.drug) LIKE '%fluoxetine%'
                      OR LOWER(pr.drug) LIKE '%paroxetine%'
                      OR LOWER(pr.drug) LIKE '%citalopram%'
                      OR LOWER(pr.drug) LIKE '%escitalopram%'
                      OR LOWER(pr.drug) LIKE '%venlafaxine%'
                      OR LOWER(pr.drug) LIKE '%duloxetine%'
                      OR LOWER(pr.drug) LIKE '%trazodone%'
                      OR LOWER(pr.drug) LIKE '%triptan%'
                      OR LOWER(pr.drug) LIKE '%linezolid%'
                    THEN 1 ELSE 0 END ) AS serotonergic_flag
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.subject_id = pr.subject_id AND c.hadm_id = pr.hadm_id
    AND pr.starttime BETWEEN c.admittime AND DATETIME_ADD(c.admittime, INTERVAL 24 HOUR)
  GROUP BY c.subject_id, c.hadm_id
),
complexity_stats AS (
  SELECT m.*,
         c.admittime, c.dischtime, c.hospital_expire_flag,
         NTILE(4) OVER (ORDER BY complexity) AS complexity_quartile,
         PERCENT_RANK() OVER (ORDER BY complexity) AS complexity_percentile,
         DATETIME_DIFF(c.dischtime, c.admittime, DAY) AS los_days
  FROM meds24h m
  JOIN cohort c
    ON m.subject_id = c.subject_id AND m.hadm_id = c.hadm_id
),
topq AS (
  SELECT * FROM complexity_stats WHERE complexity_quartile = 4
)
SELECT serotonergic_flag,
       AVG(los_days) AS avg_los_days_top_q,
       AVG(hospital_expire_flag) AS mortality_rate_top_q
FROM topq
GROUP BY serotonergic_flag
ORDER BY serotonergic_flag;