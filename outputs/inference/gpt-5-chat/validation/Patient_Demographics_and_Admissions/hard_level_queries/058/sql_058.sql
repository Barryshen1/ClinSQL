WITH cohort AS (
    SELECT
        a.subject_id,
        a.hadm_id,
        a.admittime,
        a.dischtime,
        p.gender,
        p.anchor_age,
        a.insurance,
        a.admission_location,
        d.long_title AS principal_dx,
        TIMESTAMP_DIFF(a.dischtime, a.admittime, DAY) AS los_days
    FROM `physionet-data.mimiciv_3_1_hosp.admissions` a
    JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON a.subject_id = p.subject_id
    JOIN `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` dx
        ON a.subject_id = dx.subject_id
        AND a.hadm_id = dx.hadm_id
        AND dx.seq_num = 1
    JOIN `physionet-data.mimiciv_3_1_hosp.d_icd_diagnoses` d
        ON dx.icd_code = d.icd_code
        AND dx.icd_version = d.icd_version
    WHERE p.gender = 'M'
      AND p.anchor_age BETWEEN 50 AND 60
      AND a.insurance = 'Medicare'
      AND LOWER(a.admission_location) LIKE 'emergency%'
      AND (
            LOWER(d.long_title) LIKE '%lower gastrointestinal%'
         OR LOWER(d.long_title) LIKE '%lower gi%'
         OR LOWER(d.long_title) LIKE '%rectal bleed%'
         OR LOWER(d.long_title) LIKE '%rectal bleeding%'
         OR LOWER(d.long_title) LIKE '%colon bleed%'
         OR LOWER(d.long_title) LIKE '%colon bleeding%'
      )
),
readmission_flag AS (
    SELECT
        c.*,
        CASE WHEN EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.admissions` a2
            WHERE a2.subject_id = c.subject_id
              AND a2.admittime > c.dischtime
              AND a2.admittime <= TIMESTAMP_ADD(c.dischtime, INTERVAL 30 DAY)
        ) THEN 1 ELSE 0 END AS readmitted_30d
    FROM cohort c
),
stats AS (
    SELECT
        readmitted_30d,
        COUNT(*) AS n_admissions,
        -- BigQuery: median via APPROX_QUANTILES
        APPROX_QUANTILES(los_days, 2)[OFFSET(1)] AS median_los,
        100 * SUM(CASE WHEN los_days > 6 THEN 1 ELSE 0 END) / COUNT(*) AS pct_los_gt6
    FROM readmission_flag
    GROUP BY readmitted_30d
),
overall_rate AS (
    SELECT 
        ROUND(100.0 * SUM(CASE WHEN readmitted_30d = 1 THEN 1 ELSE 0 END) / COUNT(*), 2) 
        AS overall_readmission_rate_pct
    FROM readmission_flag
)
SELECT
    s.readmitted_30d,
    ROUND(s.median_los, 2) AS median_los_days,
    ROUND(s.pct_los_gt6, 2) AS pct_los_over_6_days,
    o.overall_readmission_rate_pct
FROM stats s
CROSS JOIN overall_rate o
ORDER BY s.readmitted_30d;