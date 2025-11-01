WITH admissions_cohort AS (
    SELECT
        ad.subject_id,
        ad.hadm_id,
        DATE_DIFF(ad.dischtime, ad.admittime, DAY) AS los_days,
        -- Determine if this admission had an ICU stay
        MAX(CASE WHEN icu.stay_id IS NOT NULL THEN 'Yes' ELSE 'No' END) AS had_icu_stay
    FROM
        `physionet-data.mimiciv_3_1_hosp.admissions` AS ad
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.patients` AS p
        ON ad.subject_id = p.subject_id
    LEFT JOIN
        `physionet-data.mimiciv_3_1_icu.icustays` AS icu
        ON ad.hadm_id = icu.hadm_id
    WHERE
        p.gender = 'F'
        AND p.anchor_age BETWEEN 40 AND 50
        AND DATE_DIFF(ad.dischtime, ad.admittime, DAY) BETWEEN 1 AND 7
        -- Identify patients with ischemic stroke (primary diagnosis based on ICD-9 and ICD-10)
        AND EXISTS (
            SELECT 1
            FROM `physionet-data.mimiciv_3_1_hosp.diagnoses_icd` AS di
            WHERE
                di.subject_id = ad.subject_id
                AND di.hadm_id = ad.hadm_id
                AND di.seq_num = 1 -- Often, seq_num = 1 is the principal diagnosis
                AND (
                    (di.icd_version = 10 AND di.icd_code LIKE 'I63%') -- ICD-10 for ischemic stroke
                    OR
                    (di.icd_version = 9 AND di.icd_code LIKE '434%') -- ICD-9 for occlusion of cerebral arteries (ischemic stroke)
                )
        )
    GROUP BY
        ad.subject_id,
        ad.hadm_id,
        los_days
),
imaging_procedures_per_admission AS (
    SELECT
        pr.hadm_id,
        COUNT(pr.icd_code) AS num_imaging_procedures
    FROM
        `physionet-data.mimiciv_3_1_hosp.procedures_icd` AS pr
    INNER JOIN
        `physionet-data.mimiciv_3_1_hosp.d_icd_procedures` AS dip
        ON pr.icd_code = dip.icd_code AND pr.icd_version = dip.icd_version
    WHERE
        (pr.icd_version = 9 AND (
                pr.icd_code BETWEEN '87.0' AND '87.99' -- Diagnostic Radiology (e.g., X-ray, Fluoroscopy, Myelogram, etc.)
                OR pr.icd_code LIKE '88.3%' -- Computed tomography (CT scan)
                OR pr.icd_code LIKE '88.4%' -- Angiography (e.g., cerebral, head, neck, abdominal)
                OR pr.icd_code LIKE '88.7%' -- Diagnostic ultrasound (e.g., heart, brain, abdomen)
                OR pr.icd_code LIKE '88.9%' -- Magnetic resonance imaging (MRI) and other unspecified diagnostic imaging
            )
        )
        OR (pr.icd_version = 10 AND (
                -- Common ICD-10 PCS terms for imaging procedures
                UPPER(dip.long_title) LIKE '%CT SCAN%'
                OR UPPER(dip.long_title) LIKE '%MRI%'
                OR UPPER(dip.long_title) LIKE '%ULTRASOUND%'
                OR UPPER(dip.long_title) LIKE '%X-RAY%'
                OR UPPER(dip.long_title) LIKE '%RADIOGRAPH%'
                OR UPPER(dip.long_title) LIKE '%ANGIOGR%' -- Includes Angiography, Arteriography, Venography
                OR UPPER(dip.long_title) LIKE '%ECHOCARDIOGR%'
                OR UPPER(dip.long_title) LIKE '%PET SCAN%'
                OR UPPER(dip.long_title) LIKE '%SCINTIGRAPH%'
            )
        )
    GROUP BY
        pr.hadm_id
)
SELECT
    ac.had_icu_stay,
    CASE
        WHEN ac.los_days >= 1 AND ac.los_days <= 4 THEN '1-4 days'
        WHEN ac.los_days >= 5 AND ac.los_days <= 7 THEN '5-7 days'
        ELSE 'Other' -- This should not occur given the initial LOS filter
    END AS stay_duration_group,
    AVG(COALESCE(ip.num_imaging_procedures, 0)) AS mean_imaging_procedures_per_admission,
    MIN(COALESCE(ip.num_imaging_procedures, 0)) AS min_imaging_procedures_per_admission,
    MAX(COALESCE(ip.num_imaging_procedures, 0)) AS max_imaging_procedures_per_admission
FROM
    admissions_cohort AS ac
LEFT JOIN
    imaging_procedures_per_admission AS ip
    ON ac.hadm_id = ip.hadm_id
GROUP BY
    ac.had_icu_stay,
    stay_duration_group
ORDER BY
    ac.had_icu_stay DESC,
    stay_duration_group;