WITH acs_patients AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        p.anchor_age,
        p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND d.icd_version = 10
            AND d.icd_code IN (
                'I200', 'I210', 'I211', 'I212', 'I213', 'I214',
                'I220', 'I221', 'I222', 'I228', 'I229'
            )
      )
),

control_patients AS (
    SELECT 
        a.subject_id, 
        a.hadm_id, 
        a.admittime, 
        a.dischtime, 
        a.hospital_expire_flag,
        p.anchor_age,
        p.anchor_year
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p 
        ON a.subject_id = p.subject_id
    WHERE p.gender = 'F'
      AND (p.anchor_age + (EXTRACT(YEAR FROM a.admittime) - p.anchor_year)) BETWEEN 53 AND 63
      AND NOT EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.hadm_id = a.hadm_id
            AND d.icd_version = 10
            AND d.icd_code IN (
                'I200', 'I210', 'I211', 'I212', 'I213', 'I214',
                'I220', 'I221', 'I222', 'I228', 'I229'
            )
      )
),

lab_scores_acs AS (
    SELECT 
        a.hadm_id,
        a.hospital_expire_flag,
        a.admittime,
        a.dischtime,
        COUNT(DISTINCT CASE WHEN l.flag IN ('H', 'L') THEN l.itemid END) AS lab_score
    FROM acs_patients a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON a.hadm_id = l.hadm_id
        AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    GROUP BY a.hadm_id, a.hospital_expire_flag, a.admittime, a.dischtime
),

lab_scores_control AS (
    SELECT 
        a.hadm_id,
        COUNT(DISTINCT CASE WHEN l.flag IN ('H', 'L') THEN l.itemid END) AS lab_score
    FROM control_patients a
    LEFT JOIN `physionet-data.mimiciv_3_1_hosp.labevents` l 
        ON a.hadm_id = l.hadm_id
        AND l.charttime BETWEEN a.admittime AND DATETIME_ADD(a.admittime, INTERVAL 72 HOUR)
    GROUP BY a.hadm_id
),

acs_quartiles AS (
    SELECT 
        quartile,
        AVG(hospital_expire_flag) * 100 AS mortality_rate,
        AVG(DATETIME_DIFF(dischtime, admittime, DAY)) AS avg_los
    FROM (
        SELECT 
            NTILE(4) OVER (ORDER BY lab_score) AS quartile,
            hospital_expire_flag,
            admittime,
            dischtime
        FROM lab_scores_acs
    ) AS sub
    GROUP BY quartile
),

control_avg AS (
    SELECT AVG(lab_score) AS control_avg_score
    FROM lab_scores_control
),

acs_avg AS (
    SELECT AVG(lab_score) AS acs_avg_score
    FROM lab_scores_acs
)

SELECT 
    q.quartile,
    q.mortality_rate,
    q.avg_los,
    a.acs_avg_score,
    c.control_avg_score
FROM acs_quartiles q
CROSS JOIN acs_avg a
CROSS JOIN control_avg c;