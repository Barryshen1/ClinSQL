WITH thiazide_prescriptions AS (
    SELECT
        p.subject_id,
        pr.starttime,
        pr.stoptime,
        DATE_DIFF(pr.stoptime, pr.starttime, DAY) AS duration_days
    FROM `physionet-data.mimiciv_3_1_hosp.prescriptions` pr
    INNER JOIN `physionet-data.mimiciv_3_1_hosp.patients` p
        ON pr.subject_id = p.subject_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 90 AND 100
        AND (pr.drug LIKE '%chlorthalidone%' OR pr.drug LIKE '%indapamide%' OR pr.drug LIKE '%metolazone%')
        AND pr.stoptime IS NOT NULL
)
SELECT
    APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS q1,
    APPROX_QUANTILES(duration_days, 4)[OFFSET(2)] AS median,
    APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] AS q3,
    APPROX_QUANTILES(duration_days, 4)[OFFSET(3)] - APPROX_QUANTILES(duration_days, 4)[OFFSET(1)] AS iqr
FROM thiazide_prescriptions;