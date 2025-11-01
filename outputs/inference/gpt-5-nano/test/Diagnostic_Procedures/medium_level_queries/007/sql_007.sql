WITH acs_roles AS (
  SELECT hadm_id,
         MAX(CASE WHEN seq_num = 1
                  AND (icd_code LIKE '410%' OR icd_code LIKE '411%' OR icd_code LIKE '412%' OR icd_code LIKE '413%' OR icd_code LIKE '414%')
                 THEN 1 ELSE 0 END) AS has_primary,
         MAX(CASE WHEN seq_num > 1
                  AND (icd_code LIKE '410%' OR icd_code LIKE '411%' OR icd_code LIKE '412%' OR icd_code LIKE '413%' OR icd_code LIKE '414%')
                 THEN 1 ELSE 0 END) AS has_secondary
  FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd`
  WHERE icd_version = 9
  GROUP BY hadm_id
),

admissions_age AS (
  SELECT a.hadm_id,
         a.subject_id,
         a.admittime,
         a.dischtime,
         (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) AS age_at_admit
  FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON a.subject_id = p.subject_id
),

cohort AS (
  SELECT aa.hadm_id,
         aa.subject_id,
         aa.admittime,
         aa.dischtime,
         aa.age_at_admit,
         TIMESTAMP_DIFF(aa.dischtime, aa.admittime, DAY) AS LOS_days,
         CASE
           WHEN TIMESTAMP_DIFF(aa.dischtime, aa.admittime, DAY) BETWEEN 1 AND 4 THEN '1-4'
           WHEN TIMESTAMP_DIFF(aa.dischtime, aa.admittime, DAY) BETWEEN 5 AND 8 THEN '5-8'
           ELSE NULL
         END AS los_group,
         CASE
           WHEN ar.has_primary = 1 THEN 'primary'
           WHEN ar.has_primary = 0 AND ar.has_secondary = 1 THEN 'secondary'
           ELSE NULL
         END AS acs_role
  FROM admissions_age aa
  LEFT JOIN acs_roles ar
    ON aa.hadm_id = ar.hadm_id
  JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
    ON aa.subject_id = p.subject_id
  WHERE (ar.has_primary = 1 OR ar.has_secondary = 1)
    AND aa.age_at_admit BETWEEN 50 AND 60
    AND p.gender IN ('F', 'Female', 'FEMALE')
),

diag_counts AS (
  SELECT c.hadm_id,
         c.subject_id,
         c.los_group,
         c.acs_role,
         SUM(CASE
               WHEN UPPER(IFNULL(dip.long_title, '')) LIKE '%DIAGNOSTIC%'
               THEN 1 ELSE 0
             END) AS diagnostic_proc_count
  FROM cohort c
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.procedures_icd` pc
    ON c.hadm_id = pc.hadm_id
   AND c.subject_id = pc.subject_id
  LEFT JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` dip
    ON pc.icd_code = dip.icd_code
   AND dip.icd_version = 9
  GROUP BY c.hadm_id, c.subject_id, c.los_group, c.acs_role
)

SELECT los_group,
       acs_role,
       quantiles[OFFSET(1)] AS p25,
       quantiles[OFFSET(2)] AS p50,
       quantiles[OFFSET(3)] AS p75
FROM (
  SELECT los_group, acs_role, APPROX_QUANTILES(diagnostic_proc_count, 4) AS quantiles
  FROM diag_counts
  WHERE los_group IS NOT NULL AND acs_role IS NOT NULL
  GROUP BY los_group, acs_role
) AS t
ORDER BY los_group, acs_role;