WITH arb_prescriptions AS (
    SELECT
        p.subject_id,
        pr.hadm_id,  -- Changed from p.hadm_id to pr.hadm_id
        pr.starttime,
        pr.stoptime,
        DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
        ON a.subject_id = pr.subject_id AND a.hadm_id = pr.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 38 AND 48
        AND (
            pr.drug LIKE '%losartan%' OR
            pr.drug LIKE '%valsartan%' OR
            pr.drug LIKE '%irbesartan%' OR
            pr.drug LIKE '%candesartan%' OR
            pr.drug LIKE '%telmisartan%' OR
            pr.drug LIKE '%olmesartan%' OR
            pr.drug LIKE '%eprosartan%' OR
            pr.drug LIKE '%azilsartan%'
        )
        AND pr.starttime IS NOT NULL
        AND pr.stoptime IS NOT NULL
        AND pr.starttime >= a.admittime
        AND pr.stoptime <= a.dischtime
)
SELECT
    APPROX_QUANTILES(duration_days, 100)[OFFSET(75)] AS percentile_75_duration_days
FROM arb_prescriptions;