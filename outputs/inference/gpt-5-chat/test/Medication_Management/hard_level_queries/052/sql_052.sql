WITH female_patients AS (
    SELECT p.subject_id, p.gender, p.anchor_age
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    WHERE gender = 'F'
      AND anchor_age BETWEEN 68 AND 78
),
admissions_female AS (
    SELECT a.subject_id, a.hadm_id, a.admittime, a.dischtime, a.hospital_expire_flag
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN female_patients fp
      ON a.subject_id = fp.subject_id
),
hhs_admissions AS (
    SELECT DISTINCT a.subject_id, a.hadm_id
    FROM admissions_female a
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
      ON a.hadm_id = d.hadm_id
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` dd
      ON d.icd_code = dd.icd_code AND d.icd_version = dd.icd_version
    WHERE LOWER(dd.long_title) LIKE '%hyperosmolar%'
),
prescriptions_72hr AS (
    SELECT pr.subject_id, pr.hadm_id,
           pr.starttime, LOWER(pr.drug) AS drug
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    JOIN admissions_female a
      ON pr.hadm_id = a.hadm_id
    WHERE pr.starttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
),
complexity AS (
    SELECT hadm_id, COUNT(DISTINCT drug) AS complexity
    FROM prescriptions_72hr
    GROUP BY hadm_id
),
risk_list AS (
    SELECT 'spironolactone' AS term UNION ALL
    SELECT 'eplerenone' UNION ALL
    SELECT 'amiloride' UNION ALL
    SELECT 'triamterene' UNION ALL
    SELECT 'lisinopril' UNION ALL
    SELECT 'enalapril' UNION ALL
    SELECT 'ramipril' UNION ALL
    SELECT 'losartan' UNION ALL
    SELECT 'valsartan' UNION ALL
    SELECT 'irbesartan' UNION ALL
    SELECT 'trimethoprim'
),
risk_flags AS (
    SELECT p.hadm_id,
           SUM(CASE WHEN EXISTS (
               SELECT 1 FROM risk_list rl WHERE p.drug LIKE rl.term || '%'
           ) THEN 1 ELSE 0 END) AS risk_count
    FROM prescriptions_72hr p
    GROUP BY p.hadm_id
),
grouped AS (
    SELECT a.hadm_id,
           CASE WHEN h.hadm_id IS NOT NULL THEN 'HHS' ELSE 'All' END AS cohort,
           c.complexity,
           rf.risk_count,
           a.hospital_expire_flag,
           DATETIME_DIFF(a.dischtime, a.admittime, DAY) AS los
    FROM admissions_female a
    LEFT JOIN hhs_admissions h ON a.hadm_id = h.hadm_id
    LEFT JOIN complexity c ON a.hadm_id = c.hadm_id
    LEFT JOIN risk_flags rf ON a.hadm_id = rf.hadm_id
),
ranks AS (
    SELECT cohort, hadm_id, complexity, risk_count,
           PERCENT_RANK() OVER(PARTITION BY cohort ORDER BY complexity) AS complexity_pct,
           los, hospital_expire_flag
    FROM grouped
),
los_quartiles AS (
    SELECT cohort,
           APPROX_QUANTILES(los, 4)[OFFSET(3)] AS los_q3
    FROM ranks
    GROUP BY cohort
),
summary AS (
    SELECT r.cohort,
           -- complexity distribution
           APPROX_TOP_COUNT(complexity, 10) AS complexity_distribution,
           -- median percentile rank for those with risk interactions
           APPROX_QUANTILES(IF(risk_count >= 2, complexity_pct, NULL), 2)[OFFSET(1)] AS median_pct_rank_risk,
           -- percent affected
           100 * SUM(CASE WHEN risk_count >= 2 THEN 1 ELSE 0 END) / COUNT(*) AS percent_affected_risk,
           lq.los_q3,
           -- mortality in top quartile LOS
           100 * SUM(CASE WHEN los >= lq.los_q3 AND hospital_expire_flag=1 THEN 1 ELSE 0 END)
             / SUM(CASE WHEN los >= lq.los_q3 THEN 1 ELSE 0 END) AS mortality_topq_LOS
    FROM ranks r
    JOIN los_quartiles lq
      ON r.cohort = lq.cohort
    GROUP BY r.cohort, lq.los_q3
)
SELECT * FROM summary;