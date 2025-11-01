WITH cohort AS (
    SELECT 
        p.subject_id, 
        p.gender,
        p.anchor_age,
        p.anchor_year,
        i.hadm_id,
        i.stay_id,
        i.intime,
        i.outtime,
        i.los,
        a.hospital_expire_flag,
        p.anchor_age + (EXTRACT(YEAR FROM i.intime) - p.anchor_year) AS age_at_icu_admission
    FROM `physionet-data.mimiciv_3_1_icu.icustays` i
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON i.subject_id = p.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON i.hadm_id = a.hadm_id
    WHERE p.gender = 'F'
      AND EXISTS (
          SELECT 1
          FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` d
          WHERE d.subject_id = i.subject_id
            AND d.hadm_id = i.hadm_id
            AND (
                (d.icd_version = 9 AND d.icd_code LIKE '431%')
                OR (d.icd_version = 9 AND d.icd_code LIKE '432%')
                OR (d.icd_version = 10 AND d.icd_code LIKE 'I61%')
                OR (d.icd_version = 10 AND d.icd_code LIKE 'I62%')
            )
      )
),
cohort_filtered AS (
    SELECT *
    FROM cohort
    WHERE age_at_icu_admission BETWEEN 47 AND 57
),
instability_scores AS (
    SELECT 
        c.stay_id,
        COALESCE(SUM(
            CASE 
                WHEN ce.itemid = 220045 AND (ce.valuenum < 60 OR ce.valuenum > 100) THEN 1
                WHEN ce.itemid = 220179 AND (ce.valuenum < 90 OR ce.valuenum > 140) THEN 1
                WHEN ce.itemid = 220180 AND (ce.valuenum < 60 OR ce.valuenum > 90) THEN 1
                WHEN ce.itemid = 220210 AND (ce.valuenum < 12 OR ce.valuenum > 20) THEN 1
                WHEN ce.itemid = 223761 AND ((ce.valuenum - 32) * 5/9) NOT BETWEEN 36.0 AND 38.0 THEN 1
                WHEN ce.itemid = 223762 AND ce.valuenum NOT BETWEEN 36.0 AND 38.0 THEN 1
                ELSE 0 
            END
        ), 0) AS total_abnormal_count
    FROM cohort_filtered c
    LEFT JOIN `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON c.stay_id = ce.stay_id
        AND c.subject_id = ce.subject_id
        AND ce.charttime BETWEEN c.intime AND DATETIME_ADD(c.intime, INTERVAL 72 HOUR)
        AND ce.itemid IN (220045, 220179, 220180, 220210, 223761, 223762)
    GROUP BY c.stay_id
),
percentile_75 AS (
    SELECT 
        AVG(CASE WHEN total_abnormal_count <= 75 THEN 1.0 ELSE 0.0 END) * 100 AS percentile
    FROM instability_scores
),
p90 AS (
    SELECT 
        APPROX_QUANTILES(total_abnormal_count, 100)[OFFSET(90)] AS p90_value
    FROM instability_scores
),
top_decile AS (
    SELECT 
        c.los,
        c.hospital_expire_flag
    FROM instability_scores s
    INNER JOIN cohort_filtered c
        ON s.stay_id = c.stay_id
    WHERE s.total_abnormal_count >= (SELECT p90_value FROM p90)
)
SELECT 
    (SELECT percentile FROM percentile_75) AS percentile_for_75,
    AVG(los) AS avg_icu_los_top_decile,
    AVG(CASE WHEN hospital_expire_flag = 1 THEN 1 ELSE 0 END) * 100 AS mortality_rate_top_decile
FROM top_decile;