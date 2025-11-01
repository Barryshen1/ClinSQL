SELECT
    STDDEV(first_spo2.spo2_value) AS stddev_first_spo2_percent
FROM (
    SELECT
        ce.subject_id,
        ce.hadm_id,
        ce.valuenum AS spo2_value,
        ROW_NUMBER() OVER(PARTITION BY ce.subject_id, ce.hadm_id ORDER BY ce.charttime ASC) as rn
    FROM
        `physionet-data.mimiciv_3_1_hosp.patients` p
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.admissions` a
        ON p.subject_id = a.subject_id
    INNER JOIN
        `physionet-data.mimiciv_3_1_icu.chartevents` ce
        ON a.subject_id = ce.subject_id AND a.hadm_id = ce.hadm_id
    WHERE
        p.gender = 'M'
        AND p.anchor_age BETWEEN 77 AND 87
        AND ce.itemid = 220277 -- itemid for 'O2 saturation pulseoxymetry'
        AND ce.valuenum IS NOT NULL -- ensure a numeric value exists
        AND ce.valuenum >= 0 AND ce.valuenum <= 100 -- filter for valid SpO2 percentages
        AND ce.charttime >= a.admittime -- ensure the reading is on or after hospital admission
) AS first_spo2
WHERE
    first_spo2.rn = 1;