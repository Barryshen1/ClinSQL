SELECT
    STDDEV(
        CASE
            WHEN awans.next_admittime IS NOT NULL
                 AND TIMESTAMP_DIFF(awans.next_admittime, awans.dischtime, DAY) <= 30
            THEN 1
            ELSE 0
        END
    ) AS stddev_30_day_readmission
FROM
    (
        SELECT
            adm.subject_id,
            adm.hadm_id,
            adm.admittime,
            adm.dischtime,
            -- Determine if this specific admission has an AKI diagnosis
            MAX(CASE
                WHEN (di.icd_version = 9 AND di.icd_code LIKE '584%') OR (di.icd_version = 10 AND di.icd_code LIKE 'N17%')
                THEN 1
                ELSE 0
            END) OVER (PARTITION BY adm.hadm_id) AS has_aki_diagnosis,
            -- Get the next admission's admit_time for the same patient, considering *all* admissions
            LEAD(adm.admittime) OVER (PARTITION BY adm.subject_id ORDER BY adm.admittime) AS next_admittime
        FROM
            `physionet-data.mimiciv_3_1_hosp.admissions` adm
        INNER JOIN
            `physionet-data.mimiciv_3_1_hosp.patients` p
            ON adm.subject_id = p.subject_id
        LEFT JOIN -- Left join to ensure all admissions for the demographic are included for LEAD, but AKI status is marked
            `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` di
            ON adm.hadm_id = di.hadm_id
        WHERE
            p.gender = 'F'
            AND p.anchor_age BETWEEN 52 AND 62
    ) AS awans
WHERE
    awans.has_aki_diagnosis = 1; -- Filter to only analyze admissions that actually had an AKI diagnosis;