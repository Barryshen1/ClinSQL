WITH trauma_dx AS (
  SELECT
    hadm_id
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
  WHERE
    ( (icd_version = 9 AND REGEXP_CONTAINS(icd_code, r'^(8|9)[0-9]{2}'))
      OR (icd_version = 10 AND REGEXP_CONTAINS(icd_code, r'^[ST]')) )
  GROUP BY hadm_id
  HAVING COUNT(DISTINCT icd_code) >= 2
),
cohort AS (
  SELECT
    a.subject_id,
    a.hadm_id,
    p.gender,
    p.anchor_age,
    a.admittime,
    a.dischtime,
    a.hospital_expire_flag,
    DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los_days
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
  JOIN trauma_dx t
    ON a.hadm_id = t.hadm_id
  WHERE p.gender = 'F'
    AND p.anchor_age BETWEEN 45 AND 55
),
med_complexity AS (
  SELECT
    c.subject_id,
    c.hadm_id,
    COUNT(DISTINCT pr.drug) AS complexity_score
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    ON c.hadm_id = pr.hadm_id
    AND pr.starttime >= c.admittime
    AND pr.starttime < DATETIME_ADD(c.admittime, INTERVAL 7 DAY)
  GROUP BY c.subject_id, c.hadm_id
),
cohort_with_scores AS (
  SELECT
    c.*,
    mc.complexity_score
  FROM cohort c
  JOIN med_complexity mc
    ON c.subject_id = mc.subject_id
    AND c.hadm_id = mc.hadm_id
),
readmissions AS (
  SELECT
    subject_id,
    hadm_id,
    dischtime,
    LEAD(admittime) OVER (PARTITION BY subject_id ORDER BY admittime) AS next_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions`
),
cohort_with_readmit AS (
  SELECT
    cs.*,
    CASE
      WHEN DATETIME_DIFF(r.next_admit, cs.dischtime, DAY) <= 30
           AND DATETIME_DIFF(r.next_admit, cs.dischtime, DAY) >= 0
      THEN 1 ELSE 0
    END AS readmit_30d
  FROM cohort_with_scores cs
  JOIN readmissions r
    ON cs.subject_id = r.subject_id
    AND cs.hadm_id = r.hadm_id
),
tertiles AS (
  SELECT
    *,
    NTILE(3) OVER (ORDER BY complexity_score) AS tertile
  FROM cohort_with_readmit
)
SELECT
  tertile,
  COUNT(DISTINCT hadm_id) AS admissions,
  ROUND(AVG(complexity_score),2) AS mean_score,
  MIN(complexity_score) AS min_score,
  MAX(complexity_score) AS max_score,
  ROUND(AVG(los_days),2) AS mean_los,
  ROUND(100*AVG(hospital_expire_flag),2) AS mortality_percent,
  ROUND(100*AVG(readmit_30d),2) AS readmit_30d_percent
FROM tertiles
GROUP BY tertile
ORDER BY tertile;